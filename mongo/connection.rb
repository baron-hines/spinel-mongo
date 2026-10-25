# One connection to a server, over a transport duck: write(bytes),
# read_some(max), which returns "" once the server has closed it, and
# close. Mongo::Transport is the real one; tests pass a scripted one, so
# this file runs under both runtimes.
#
# handshake sends hello and keeps the server's limits. command and
# command_seq send one command, wait for the reply that answers it,
# decode it and raise the gem's errors. After a network or protocol
# error the connection is closed for good, and every later command
# raises SocketError: the caller opens a new one. Nothing is retried,
# since a write may have reached the server.
require "bson"
require "mongo/version"
require "mongo/errors"
require "mongo/wire"

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

    def close
      unless @closed
        @closed = true
        @transport.close
      end
      nil
    end

    # Sends one request and reads until the reply to it is whole.
    def round_trip(body, seq_id, docs)
      if @closed
        raise Mongo::Error::SocketError, "The connection to " + @address + " is closed"
      end
      id = @next_id
      @next_id += 1
      request = Mongo::Wire.op_msg(id, body, seq_id, docs)
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
        close
        raise e
      end
      if @parser.response_to != id
        close
        raise Mongo::Error::UnexpectedResponse.new(id, @parser.response_to)
      end
      @parser.document
    end
  end
end
