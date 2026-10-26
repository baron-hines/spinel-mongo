# One connection to a server, over a transport duck: write(bytes),
# read_some(max), which returns "" once the server has closed it,
# peer_closed?, which says without blocking whether it has, and close.
# Mongo::Transport is the real one; tests pass a scripted one, so this
# file runs under both runtimes.
#
# handshake sends hello and keeps the server's limits. command and
# command_seq send one command, wait for the reply that answers it,
# decode it and raise the gem's errors. After a network or protocol
# error the connection is closed for good, and every later command
# raises SocketError: the caller opens a new one. Nothing is retried,
# since a write may have reached the server. authenticate logs in with
# SCRAM after the handshake.
#
# A Mutex holds each request and its reply together, so threads that
# share the connection take turns a round trip at a time.
require "bson"
require "mongo/version"
require "mongo/errors"
require "mongo/wire"
require "mongo/scram"

module Mongo
  class Connection
    # MongoDB 6.0. Older servers are refused at the handshake.
    MIN_WIRE_VERSION = 17
    READ_SIZE = 65536

    def initialize(transport, address)
      @transport = transport
      @address = address
      @parser = Mongo::Wire::Parser.new
      @next_id = 1
      @closed = false
      @lock = Mutex.new
      @hello = BSON::Document.new
      @max_wire_version = 0
      @max_bson_object_size = 16 * 1024 * 1024
      @max_message_size = 48_000_000
      @max_write_batch_size = 100_000
    end

    def address
      @address
    end

    def closed?
      @closed
    end

    # The hello reply, once handshake has run.
    def hello
      @hello
    end

    def max_wire_version
      @max_wire_version
    end

    def max_bson_object_size
      @max_bson_object_size
    end

    def max_message_size
      @max_message_size
    end

    def max_write_batch_size
      @max_write_batch_size
    end

    # The client metadata hello carries, in the gem's shape.
    def self.client_document(app_name)
      doc = BSON::Document.new
      doc["application"] = { "name" => app_name } if app_name != ""
      doc["driver"] = { "name" => "spinel-mongo", "version" => Mongo::VERSION }
      dash = RUBY_PLATFORM.index("-")
      arch = dash.nil? ? RUBY_PLATFORM : RUBY_PLATFORM[0, dash]
      os = dash.nil? ? "unknown" : RUBY_PLATFORM[dash + 1, RUBY_PLATFORM.length - dash - 1]
      doc["os"] = { "type" => os, "name" => os, "architecture" => arch }
      engine = RUBY_ENGINE == "spinel" ? "Spinel (Ruby " + RUBY_VERSION + ")" : "Ruby " + RUBY_VERSION
      doc["platform"] = engine + ", " + RUBY_PLATFORM
      doc
    end

    # The first command on a connection. sasl_user, "<authSource>.<user>"
    # when there are credentials, asks the server which SCRAM mechanisms
    # the user has.
    def self.hello_command(client, sasl_user)
      cmd = BSON::Document.new
      cmd["hello"] = 1
      cmd["helloOk"] = true
      cmd["compression"] = []
      cmd["client"] = client
      cmd["saslSupportedMechs"] = sasl_user if sasl_user != ""
      cmd["$db"] = "admin"
      cmd
    end

    # Sends hello and keeps the reply and its limits. A connection that
    # breaks or times out here raises NoServerAvailable, as the gem's
    # server selection does when it finds no server, and a server older
    # than MongoDB 6.0 raises UnsupportedFeatures.
    def handshake(app_name = "", sasl_user = "")
      cmd = Connection.hello_command(Connection.client_document(app_name), sasl_user)
      reply = BSON::Document.new
      begin
        reply = command(cmd)
      rescue Mongo::Error::SocketError => e
        raise Mongo::Error::NoServerAvailable, "No server is available at " + @address + ": " + e.message
      rescue Mongo::Error::TimeoutError => e
        raise Mongo::Error::NoServerAvailable, "No server is available at " + @address + ": " + e.message
      end
      wire = reply["maxWireVersion"]
      wire = 0 unless wire.is_a?(Integer)
      if wire < MIN_WIRE_VERSION
        close
        raise Mongo::Error::UnsupportedFeatures,
              "Server at (" + @address + ") reports wire version (" + wire.to_s +
              "), but spinel-mongo requires at least (" + MIN_WIRE_VERSION.to_s + ")."
      end
      @hello = reply
      @max_wire_version = wire
      @max_bson_object_size = limit(reply, "maxBsonObjectSize", @max_bson_object_size)
      @max_message_size = limit(reply, "maxMessageSizeBytes", @max_message_size)
      @max_write_batch_size = limit(reply, "maxWriteBatchSize", @max_write_batch_size)
      reply
    end

    def limit(reply, key, default)
      v = reply[key]
      v.is_a?(Integer) ? v : default
    end

    # One command; its reply, decoded. Raises OperationFailure as the
    # gem's Database#command does: when ok isn't 1, and when the reply
    # carries write errors or a write concern error.
    def command(body)
      command_seq(body, "", [])
    end

    # A command with documents in a kind 1 section under seq_id, as
    # insert sends its documents.
    def command_seq(body, seq_id, docs)
      reply = round_trip(body, seq_id, docs)
      raise Mongo::Error::OperationFailure.from_reply(reply) if Mongo::Error::OperationFailure.failure?(reply)
      reply
    end

    # A write of many documents: write errors and a write concern error
    # raise BulkWriteError with the reply as its result, as the gem's
    # insert_many and the *_many writes do. A reply with ok not 1 still
    # raises OperationFailure.
    def write_seq(body, seq_id, docs)
      reply = round_trip(body, seq_id, docs)
      if reply["ok"] != 1
        raise Mongo::Error::OperationFailure.from_reply(reply)
      end
      if reply.key?("writeErrors") || reply.key?("writeConcernError")
        raise Mongo::Error::BulkWriteError.new(reply)
      end
      reply
    end

    # Logs in with SCRAM as user on the auth_source database. mechanism is
    # Scram::SHA256 or Scram::SHA1, or "" to choose as the gem does:
    # SCRAM-SHA-256 when the handshake's saslSupportedMechs lists it (pass
    # "<auth_source>.<user>" to handshake for that), else SCRAM-SHA-1.
    # database only names the target in the error message.
    #
    # A refusal raises Mongo::Auth::Unauthorized with the gem's message, a
    # server that fails the SCRAM checks raises the gem's InvalidNonce,
    # InvalidSignature or InsufficientIterationCount, and either way the
    # connection is closed, as the gem drops a connection that failed to
    # authenticate.
    def authenticate(user, password, database, auth_source, mechanism = "")
      used = mechanism
      if used == ""
        mechs = @hello["saslSupportedMechs"]
        used = mechs.is_a?(Array) && mechs.include?(Scram::SHA256) ? Scram::SHA256 : Scram::SHA1
      end
      scram = Scram.new(used, user, Scram.secret(used, user, password), Scram.nonce)
      begin
        start = BSON::Document.new
        start["saslStart"] = 1
        start["autoAuthorize"] = 1
        start["mechanism"] = used
        start["payload"] = BSON::Binary.new(scram.client_first)
        start["options"] = { "skipEmptyExchange" => true }
        start["$db"] = auth_source
        reply = sasl_step(start, user, database, auth_source, used)
        conversation = reply["conversationId"]
        step = BSON::Document.new
        step["saslContinue"] = 1
        step["payload"] = BSON::Binary.new(scram.client_final(payload_of(reply)))
        step["conversationId"] = conversation
        step["$db"] = auth_source
        reply = sasl_step(step, user, database, auth_source, used)
        scram.verify(payload_of(reply))
        unless reply["done"] == true
          last = BSON::Document.new
          last["saslContinue"] = 1
          last["payload"] = BSON::Binary.new("")
          last["conversationId"] = conversation
          last["$db"] = auth_source
          reply = sasl_step(last, user, database, auth_source, used)
        end
        unless reply["done"] == true
          raise Mongo::Error::InvalidServerAuthResponse,
                "Server did not respond with {done: true} after finalizing the conversation"
        end
        raise Mongo::Error::MissingScramServerSignature unless scram.verified?
      rescue Mongo::Error => e
        close
        raise e
      rescue Mongo::Error::AuthError => e
        close
        raise e
      end
      used
    end

    # One SCRAM step: a reply with ok not 1 raises Unauthorized.
    def sasl_step(cmd, user, database, auth_source, used)
      reply = round_trip(cmd, "", [])
      if reply["ok"] != 1
        code = reply["code"]
        code = nil unless code.is_a?(Integer)
        text = reply["errmsg"]
        text = "" unless text.is_a?(String)
        code_name = reply["codeName"]
        code_name = nil unless code_name.is_a?(String)
        detail = Mongo::Error::OperationFailure.build_message(code, code_name, text)
        raise Mongo::Auth::Unauthorized.new(
          Mongo::Auth::Unauthorized.build_message(user, database, auth_source, used, detail), code)
      end
      reply
    end

    # A SCRAM reply's payload, as text.
    def payload_of(reply)
      payload = reply["payload"]
      unless payload.is_a?(BSON::Binary)
        raise Mongo::Error::InvalidServerAuthResponse, "Payload malformed: missing payload"
      end
      payload.data.dup.force_encoding("UTF-8")
    end

    # Closes the connection once no round trip is under way on it, so a
    # thread waiting for its reply never has the socket closed under it.
    def close
      @lock.lock
      begin
        drop
      ensure
        @lock.unlock
      end
    end

    # close, for a round trip that holds the lock already.
    def drop
      unless @closed
        @closed = true
        @transport.close
      end
      nil
    end

    # Whether the connection can't take another request: it is closed,
    # or the server has closed its end (or sent bytes nothing asked for)
    # since the last reply. Checked under the lock, so it never reads
    # while a reply is on its way.
    def stale?
      @lock.lock
      begin
        @closed || @transport.peer_closed?
      ensure
        @lock.unlock
      end
    end

    # Sends one request and reads until the reply to it is whole.
    def round_trip(body, seq_id, docs)
      @lock.lock
      begin
        check_open
        id = @next_id
        @next_id += 1
        exchange(id, Mongo::Wire.op_msg(id, body, seq_id, docs))
      ensure
        @lock.unlock
      end
    end

    # round_trip with the kind 1 documents already encoded. The reply is
    # returned as it is, failed or not, for the caller to read.
    def round_trip_encoded(body, seq_id, encoded_docs)
      @lock.lock
      begin
        check_open
        id = @next_id
        @next_id += 1
        exchange(id, Mongo::Wire.op_msg_encoded(id, body, seq_id, encoded_docs))
      ensure
        @lock.unlock
      end
    end

    def check_open
      if @closed
        raise Mongo::Error::SocketError, "The connection to " + @address + " is closed"
      end
      nil
    end

    def exchange(id, request)
      begin
        @transport.write(request)
        until @parser.try_next
          chunk = @transport.read_some(READ_SIZE)
          if chunk.bytesize == 0
            raise Mongo::Error::SocketError, "The server at " + @address + " closed the connection"
          end
          @parser.feed(chunk)
        end
      rescue Mongo::Error => e
        drop
        raise e
      end
      if @parser.response_to != id
        drop
        raise Mongo::Error::UnexpectedResponse.new(id, @parser.response_to)
      end
      @parser.document
    end
  end
end
