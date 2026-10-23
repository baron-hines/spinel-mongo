# The encoder: an object that appends everything to one binary buffer
# it holds in an ivar, writing each document's length into its first four
# bytes once its end is known. Building with + copies the whole String
# each time, and so does appending to a String handed down as a method
# parameter in some programs (see the README's Spinel notes), so the
# buffer never leaves the object until it is done. Each method returns
# nil: one that returned the buffer (the value of its last <<) would hand
# it out, and Spinel then copies it on every later append.
module BSON
  class Encoder
    INT32_MIN = -2147483648
    INT32_MAX = 2147483647
    INT64_MIN = -9223372036854775807 - 1
    INT64_MAX = 9223372036854775807

    # CRuby's NaN bytes, which the gem writes. Spinel's Float::NAN packs
    # with the sign bit set, so every NaN is written as these.
    NAN_BYTES = [0, 0, 0, 0, 0, 0, 0xf8, 0x7f].pack("C*").freeze

    def initialize
      @buf = "".b
    end

    # The bytes written so far.
    def bytes
      @buf
    end

    def document(doc)
      start = @buf.bytesize
      @buf << "\x00\x00\x00\x00".b
      doc.each { |k, v| element(k.to_s, v) }
      @buf << "\x00".b
      patch_length(start)
      nil
    end

    def array(list)
      start = @buf.bytesize
      @buf << "\x00\x00\x00\x00".b
      i = 0
      while i < list.length
        element(i.to_s, list[i])
        i += 1
      end
      @buf << "\x00".b
      patch_length(start)
      nil
    end

    def patch_length(start)
      n = @buf.bytesize - start
      @buf.setbyte(start, n & 0xff)
      @buf.setbyte(start + 1, (n >> 8) & 0xff)
      @buf.setbyte(start + 2, (n >> 16) & 0xff)
      @buf.setbyte(start + 3, (n >> 24) & 0xff)
    end

    def element(key, v)
      if v.is_a?(Float)
        header(0x01, key)
        @buf << (v.nan? ? NAN_BYTES : [v].pack("E"))
      elsif v.is_a?(String)
        header(0x02, key)
        string(v)
      elsif v.is_a?(Symbol)
        header(0x02, key)
        string(v.to_s)
      elsif v.is_a?(Hash)
        header(0x03, key)
        document(v)
      elsif v.is_a?(Array)
        header(0x04, key)
        array(v)
      elsif v.is_a?(BSON::Binary)
        header(0x05, key)
        binary(v)
      elsif v.is_a?(BSON::ObjectId)
        header(0x07, key)
        @buf << v.data
      elsif v == true
        header(0x08, key)
        @buf << "\x01".b
      elsif v == false
        header(0x08, key)
        @buf << "\x00".b
      elsif v.is_a?(Time)
        header(0x09, key)
        @buf << [v.to_i * 1000 + v.usec / 1000].pack("q<")
      elsif v.nil?
        header(0x0A, key)
      elsif v.is_a?(Integer)
        if v >= INT32_MIN && v <= INT32_MAX
          header(0x10, key)
          @buf << [v].pack("l<")
        elsif v >= INT64_MIN && v <= INT64_MAX
          header(0x12, key)
          @buf << [v].pack("q<")
        else
          raise RangeError, v.to_s + " is out of range for int64"
        end
      elsif v.is_a?(BSON::Int64)
        header(0x12, key)
        @buf << [v.value].pack("q<")
      else
        raise BSON::Error::UnserializableClass,
              "Value does not define its BSON serialized type: " + v.inspect
      end
      nil
    end

    def header(type, key)
      @buf << [type].pack("C")
      cstring(key)
      nil
    end

    def cstring(s)
      b = s.b
      unless b.byteindex("\x00".b, 0).nil?
        raise ArgumentError, "Key " + s.inspect + " contains null bytes"
      end
      @buf << b
      @buf << "\x00".b
      nil
    end

    def string(s)
      b = s.b
      @buf << [b.bytesize + 1].pack("l<")
      @buf << b
      @buf << "\x00".b
      nil
    end

    # Subtype 2 (:old) repeats the length inside the data, as the gem
    # writes it.
    def binary(bin)
      data = bin.data
      if bin.type == :old
        @buf << [data.bytesize + 4].pack("l<")
        @buf << [2].pack("C")
        @buf << [data.bytesize].pack("l<")
      else
        @buf << [data.bytesize].pack("l<")
        @buf << [bin.subtype].pack("C")
      end
      @buf << data
      nil
    end
  end
end
