# The wire layer: OP_MSG, the only message spinel-mongo sends or reads.
# Mongo::Wire.op_msg builds a request's bytes. Mongo::Wire::Parser is fed
# whatever the socket returns and cuts whole replies out of the stream;
# try_next answers true or false and leaves the reply in ivars, so no
# call returns a value-or-nil. Both are pure: no socket and no state
# beyond the parser's buffer.
require "bson"
require "mongo/errors"

module Mongo
  module Wire
    OP_MSG = 2013
    HEADER_SIZE = 16

    # Flag bits. Bits 0 to 15 are required: a reader must refuse a
    # message with one it doesn't know.
    CHECKSUM_PRESENT = 1
    MORE_TO_COME = 2
    REQUIRED_BITS = 0xffff

    # The gem's default limit on a reply's length, 48 MiB.
    MAX_MESSAGE_SIZE = 50_331_648

    # A request: the command as the kind 0 section, and, unless seq_docs
    # is empty, one kind 1 section holding seq_docs under seq_id, as the
    # gem sends insert's documents. Flags are 0 and responseTo is 0.
    def self.op_msg(request_id, body, seq_id = "", seq_docs = [])
      enc = BSON::Encoder.new
      enc.int32(0)
      enc.int32(request_id)
      enc.int32(0)
      enc.int32(OP_MSG)
      enc.int32(0)
      enc.byte(0)
      enc.document(body)
      if seq_docs.length > 0
        enc.byte(1)
        start = enc.size
        enc.int32(0)
        enc.cstring(seq_id)
        seq_docs.each { |d| enc.document(d) }
        enc.patch_length(start)
      end
      enc.patch_length(0)
      enc.bytes
    end

    # The same request with its kind 1 documents already encoded, so a
    # caller that measured them first doesn't encode them twice.
    def self.op_msg_encoded(request_id, body, seq_id, encoded_docs)
      enc = BSON::Encoder.new
      enc.int32(0)
      enc.int32(request_id)
      enc.int32(0)
      enc.int32(OP_MSG)
      enc.int32(0)
      enc.byte(0)
      enc.document(body)
      if encoded_docs.length > 0
        enc.byte(1)
        start = enc.size
        enc.int32(0)
        enc.cstring(seq_id)
        encoded_docs.each { |d| enc.raw(d) }
        enc.patch_length(start)
      end
      enc.patch_length(0)
      enc.bytes
    end

    # The bytes op_msg_encoded adds around a request's kind 1 documents:
    # the header, the flags, both section kinds, the kind 1 size and its
    # identifier. body_size is the encoded command's size.
    def self.overhead(body_size, seq_id)
      HEADER_SIZE + 4 + 1 + body_size + 1 + 4 + seq_id.bytesize + 1
    end

    class Parser
      def initialize(max_message_size = MAX_MESSAGE_SIZE)
        @max = max_message_size
        @buf = "".b
        @pos = 0
        @frames = 0
        @length = 0
        @request_id = 0
        @response_to = 0
        @op_code = 0
        @flags = 0
        @body = "".b
        @seq_id = ""
        @seq_docs = []
      end

      # Adds bytes read from the socket. The bytes already cut out are
      # dropped first, so the buffer holds at most one partial reply plus
      # what this read brought.
      def feed(bytes)
        if @pos > 0
          @buf = @buf.byteslice(@pos, @buf.bytesize - @pos)
          @pos = 0
        end
        @buf << bytes
        nil
      end

      # Bytes fed but not yet cut into a reply.
      def buffered
        @buf.bytesize - @pos
      end

      # Replies cut so far.
      def frames
        @frames
      end

      def length
        @length
      end

      def request_id
        @request_id
      end

      def response_to
        @response_to
      end

      def op_code
        @op_code
      end

      def flags
        @flags
      end

      # The kind 0 section's document, as raw BSON bytes.
      def body
        @body
      end

      # The kind 0 section's document, decoded.
      def document
        BSON.decode(@body)
      end

      # The kind 1 section's identifier, or "" when the reply has none.
      def seq_id
        @seq_id
      end

      # The kind 1 section's documents, as raw BSON bytes each.
      def seq_docs
        @seq_docs
      end

      # true when a whole reply was cut from the buffer, and the readers
      # above now describe it; false when more bytes are needed. Raises
      # MaxMessageSize, UnsupportedMessageType or ProtocolError when the
      # stream holds something that isn't an OP_MSG reply.
      def try_next
        left = @buf.bytesize - @pos
        return false if left < 4
        len = int32_at(@buf, @pos)
        if len < HEADER_SIZE + 5
          raise Mongo::Error::ProtocolError, "Message length " + len.to_s +
                                             " is too small for an OP_MSG"
        end
        raise Mongo::Error::MaxMessageSize.new(@max) if len > @max
        return false if left < len
        frame = @buf.byteslice(@pos, len)
        @pos += len
        if @pos == @buf.bytesize
          @buf = "".b
          @pos = 0
        end
        read_frame(frame)
        @frames += 1
        true
      end

      def read_frame(frame)
        len = frame.bytesize
        op = int32_at(frame, 12)
        if op != OP_MSG
          raise Mongo::Error::UnsupportedMessageType,
                "Detected unknown message type with op code: " + op.to_s + "."
        end
        flags = frame.byteslice(16, 4).unpack1("V")
        unknown = flags & REQUIRED_BITS & ~(CHECKSUM_PRESENT | MORE_TO_COME)
        if unknown != 0
          raise Mongo::Error::ProtocolError, "Unknown required OP_MSG flag bits: " + unknown.to_s
        end
        if (flags & MORE_TO_COME) != 0
          raise Mongo::Error::ProtocolError, "Reply has moreToCome set, but no request asked for it"
        end
        stop = len
        stop -= 4 if (flags & CHECKSUM_PRESENT) != 0
        @length = len
        @request_id = int32_at(frame, 4)
        @response_to = int32_at(frame, 8)
        @op_code = op
        @flags = flags
        @body = "".b
        @seq_id = ""
        @seq_docs = []
        seen_body = false
        pos = HEADER_SIZE + 4
        while pos < stop
          kind = frame.getbyte(pos)
          pos += 1
          size = pos + 4 <= stop ? int32_at(frame, pos) : -1
          if size < 5 || size > stop - pos
            raise Mongo::Error::ProtocolError, "OP_MSG section at " + (pos - 1).to_s +
                                               " runs past the end of the message"
          end
          if kind == 0
            if seen_body
              raise Mongo::Error::ProtocolError, "OP_MSG has more than one kind 0 section"
            end
            @body = frame.byteslice(pos, size)
            seen_body = true
          elsif kind == 1
            read_sequence(frame, pos, pos + size)
          else
            raise Mongo::Error::ProtocolError, "Unknown OP_MSG section kind " + kind.to_s
          end
          pos += size
        end
        unless seen_body
          raise Mongo::Error::ProtocolError, "OP_MSG has no kind 0 section"
        end
        nil
      end

      # A kind 1 section from start (its size field) to finish: the
      # identifier, then documents to the end.
      def read_sequence(frame, start, finish)
        pos = start + 4
        z = frame.byteindex("\x00".b, pos)
        if z.nil? || z >= finish
          raise Mongo::Error::ProtocolError, "OP_MSG kind 1 identifier is not terminated"
        end
        @seq_id = frame.byteslice(pos, z - pos).force_encoding("UTF-8")
        pos = z + 1
        while pos < finish
          dlen = pos + 4 <= finish ? int32_at(frame, pos) : -1
          if dlen < 5 || dlen > finish - pos
            raise Mongo::Error::ProtocolError, "OP_MSG kind 1 document at " + pos.to_s +
                                               " runs past the end of its section"
          end
          @seq_docs.push(frame.byteslice(pos, dlen))
          pos += dlen
        end
        nil
      end

      def int32_at(s, pos)
        s.byteslice(pos, 4).unpack1("l<")
      end
    end
  end
end
