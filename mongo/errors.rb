# The mongo gem's error classes that spinel-mongo raises, with the gem's
# messages, plus ProtocolError for a reply the driver can't read, which
# the gem has no class for. Later layers add theirs here.
#
# OperationFailure and BulkWriteError build their messages from a reply
# the way the gem's Mongo::Error::Parser does, so a program sees the
# gem's text: "[59:CommandNotFound]: no such command: 'nope'".
module Mongo
  class Error < StandardError
    # A reply whose declared length is over the limit, checked as soon
    # as its first four bytes arrive.
    class MaxMessageSize < Error
      MESSAGE = "Message exceeds allowed max message size."

      def initialize(max_size)
        super(MESSAGE + " The max is " + max_size.to_s + ".")
      end
    end

    # A reply with an op code other than OP_MSG's.
    class UnsupportedMessageType < Error
    end

    # A reply that breaks the OP_MSG framing: a length that can't hold
    # the header, a section past the end of the message, an unknown
    # section kind or required flag, or a flag the driver never asks for.
    # The byte stream can't be trusted after one, so the connection is
    # closed.
    class ProtocolError < Error
    end

    # A reply to another request than the one just sent. The connection
    # is closed, since the stream is out of step.
    class UnexpectedResponse < Error
      def initialize(expected_response_to, response_to)
        super("Unexpected response. Got response for request ID " + response_to.to_s +
              " but expected response for request ID " + expected_response_to.to_s)
      end
    end

    # A server older than the driver supports.
    class UnsupportedFeatures < Error
    end

    # Nothing to talk to: the connect was refused or timed out, or the
    # handshake failed. The gem raises this after its 30 seconds of server
    # selection; this driver raises it at once.
    class NoServerAvailable < Error
    end

    # The connection broke: the server closed it, or a write failed.
    class SocketError < Error
    end

    class TimeoutError < Error
    end

    # No reply within socket_timeout. The connection is closed, so a late
    # reply can't be read as the answer to the next command.
    class SocketTimeoutError < TimeoutError
    end

    # A reply that says the command failed: ok isn't 1, or it carries
    # write errors or a write concern error. code and code_name are the
    # server's, or nil when it sent none.
    class OperationFailure < Error
      def initialize(message, code, code_name, server_message, document)
        super(message)
        @code = code
        @code_name = code_name
        @server_message = server_message
        @document = document
      end

      def code
        @code
      end

      def code_name
        @code_name
      end

      # The server's own text, without the [code:codeName] prefix.
      def server_message
        @server_message
      end

      # The whole reply.
      def document
        @document
      end

      # Whether a reply is a failure, by the gem's rule: ok isn't 1, or
      # there are messages to report even though it is.
      def self.failure?(reply)
        reply["ok"] != 1 || OperationFailure.server_text(reply) != ""
      end

      def self.from_reply(reply)
        text = OperationFailure.server_text(reply)
        code = nil
        code_name = nil
        if reply["ok"] != 1
          code = reply["code"]
          code_name = reply["codeName"]
        end
        wce = reply["writeConcernError"]
        if code.nil? && code_name.nil? && wce.is_a?(Hash)
          code = wce["code"]
          code_name = wce["codeName"]
        end
        errors = reply["writeErrors"]
        if code.nil? && code_name.nil? && errors.is_a?(Array) && errors.length > 0
          codes = []
          errors.each do |e|
            codes.push(e["code"]) if e.is_a?(Hash) && !e["code"].nil?
          end
          if codes.length > 0 && codes.uniq.length == 1
            code = codes[0]
            errors.each do |e|
              code_name = e["codeName"] if code_name.nil? && e.is_a?(Hash)
            end
          end
        end
        OperationFailure.new(OperationFailure.build_message(code, code_name, text),
                             code, code_name, text, reply)
      end

      # The gem's Parser#build_message.
      def self.build_message(code, code_name, text)
        if !code_name.nil? && !code.nil?
          "[" + code.to_s + ":" + code_name.to_s + "]: " + text
        elsif !code_name.nil?
          "[" + code_name.to_s + "]: " + text
        elsif !code.nil?
          "[" + code.to_s + "]: " + text
        else
          text
        end
      end

      # The gem's Parser message: $err, err, errmsg, each write error's
      # errmsg, then the write concern error's, joined with ", ".
      def self.server_text(reply)
        parts = []
        ["$err", "err", "errmsg"].each do |k|
          v = reply[k]
          parts.push(v) if v.is_a?(String)
        end
        errors = reply["writeErrors"]
        if errors.is_a?(Array)
          errors.each do |e|
            parts.push(e["errmsg"]) if e.is_a?(Hash) && e["errmsg"].is_a?(String)
          end
        end
        wce = reply["writeConcernError"]
        parts.push(wce["errmsg"]) if wce.is_a?(Hash) && wce["errmsg"].is_a?(String)
        text = ""
        parts.each do |part|
          # The gem's Parser#append, which joins once the text is longer
          # than one character.
          text = text.length > 1 ? text + ", " + part : text + part
        end
        text
      end
    end

    # Write errors from a write of many documents. result is the reply,
    # with writeErrors and the counts.
    class BulkWriteError < Error
      def initialize(result)
        super(BulkWriteError.build_message(result))
        @result = result
      end

      def result
        @result
      end

      # The gem's BulkWriteError message: up to ten "[code]: errmsg"
      # fragments, "..." past ten, and "Multiple errors: " before more
      # than one.
      def self.build_message(result)
        errors = result["writeErrors"]
        return "Mongo::Error::BulkWriteError" unless errors.is_a?(Array)
        fragment = ""
        cut_short = false
        i = 0
        while i < errors.length && i < 10
          e = errors[i]
          fragment = fragment + "; " if fragment.length > 0
          if e.is_a?(Hash)
            fragment = fragment + "[" + e["code"].to_s + "]: " + e["errmsg"].to_s
          end
          if fragment.length > 3000
            cut_short = i < (errors.length < 9 ? errors.length : 9)
            break
          end
          i += 1
        end
        fragment = fragment + "..." if errors.length > 10 || cut_short
        fragment = "Multiple errors: " + fragment if errors.length > 1
        fragment
      end
    end
  end
end
