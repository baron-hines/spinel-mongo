# The decoder: a reader over one binary String with its position in an
# ivar. Every read checks the bytes are there first, so malformed input
# raises instead of reading past the end. As in the gem, a read past the
# end or a missing terminator raises RangeError, and lengths or bytes
# that disagree raise BSON::Error::BSONDecodeError.
module BSON
  class Reader
    def initialize(bytes, pos = 0)
      @s = bytes
      @pos = pos
    end

    def pos
      @pos
    end

    def need(n)
      left = @s.bytesize - @pos
      if n < 0 || n > left
        raise RangeError, "Attempted to read " + n.to_s + " bytes, but only " +
                          left.to_s + " bytes remain"
      end
    end

    def byte
      need(1)
      v = @s.getbyte(@pos)
      @pos += 1
      v
    end

    def bytes(n)
      need(n)
      v = @s.byteslice(@pos, n)
      @pos += n
      v
    end

    def int32
      need(4)
      v = @s.byteslice(@pos, 4).unpack1("l<")
      @pos += 4
      v
    end

    def int64
      need(8)
      v = @s.byteslice(@pos, 8).unpack1("q<")
      @pos += 8
      v
    end

    def double
      need(8)
      v = @s.byteslice(@pos, 8).unpack1("E")
      @pos += 8
      v
    end

    def cstring
      z = @s.byteindex("\x00".b, @pos)
      if z.nil?
        raise RangeError, "Buffer should have contained a null terminator after " + @pos.to_s
      end
      v = @s.byteslice(@pos, z - @pos).force_encoding("UTF-8")
      @pos = z + 1
      v
    end

    def string
      n = int32
      if n < 1
        raise BSON::Error::BSONDecodeError, "String length " + n.to_s + " is less than 1"
      end
      need(n)
      last = @s.getbyte(@pos + n - 1)
      if last != 0
        raise BSON::Error::BSONDecodeError, "Last byte of the string is not null: 0x" + last.to_s(16)
      end
      v = @s.byteslice(@pos, n - 1).force_encoding("UTF-8")
      @pos += n
      unless v.valid_encoding?
        raise EncodingError, "String is not valid UTF-8"
      end
      v
    end

    def document
      start = @pos
      len = int32
      finish = framed(start, len)
      doc = BSON::Document.new
      while @pos < finish - 1
        t = byte
        k = cstring
        doc[k] = value(t, "document")
      end
      close_frame(start, len, finish)
      doc
    end

    def array
      start = @pos
      len = int32
      finish = framed(start, len)
      list = []
      while @pos < finish - 1
        t = byte
        cstring
        list.push(value(t, "array"))
      end
      close_frame(start, len, finish)
      list
    end

    # Checks a document's or array's declared length fits the input and
    # returns where it ends.
    def framed(start, len)
      if len < 5
        raise RangeError, "Document length " + len.to_s + " is less than 5"
      end
      @pos = start
      need(len)
      @pos = start + 4
      start + len
    end

    def close_frame(start, len, finish)
      if @pos != finish - 1
        raise BSON::Error::BSONDecodeError, "Expected to read " + len.to_s +
                                            " bytes for the hash but read " + (@pos + 1 - start).to_s + " bytes"
      end
      if @s.getbyte(finish - 1) != 0
        raise RangeError, "Buffer should have contained a null terminator at " + (finish - 1).to_s
      end
      @pos = finish
    end

    def value(t, container)
      if t == 0x01
        double
      elsif t == 0x02
        string
      elsif t == 0x03
        document
      elsif t == 0x04
        array
      elsif t == 0x05
        binary
      elsif t == 0x07
        BSON::ObjectId.from_data(bytes(12))
      elsif t == 0x08
        b = byte
        if b > 1
          raise BSON::Error::BSONDecodeError, "Invalid boolean byte value: " + b.to_s
        end
        b == 1
      elsif t == 0x09
        ms = int64
        Time.at(ms / 1000, (ms % 1000) * 1000).utc
      elsif t == 0x0A
        nil
      elsif t == 0x10
        int32
      elsif t == 0x12
        int64
      else
        raise BSON::Error::UnsupportedType, "Detected unknown BSON type " + t.to_s +
                                            " in " + container + "."
      end
    end

    def binary
      n = int32
      sub = byte
      if n < 0
        raise BSON::Error::BSONDecodeError, "Binary length " + n.to_s + " is negative"
      end
      if sub == 2
        inner = int32
        if inner != n - 4
          raise BSON::Error::BSONDecodeError, "Binary subtype 2 length " + inner.to_s +
                                              " does not match " + (n - 4).to_s
        end
        n = inner
      end
      BSON::Binary.new(bytes(n), BSON::Binary.type_for(sub))
    end
  end
end
