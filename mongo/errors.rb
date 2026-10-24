# The mongo gem's error classes that spinel-mongo raises, with the gem's
# messages, plus ProtocolError for a reply the driver can't read, which
# the gem has no class for. Later layers add theirs here.
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
  end
end
