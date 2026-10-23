# Value classes with no Ruby built-in to stand for them.
module BSON
  # An Integer that is written as int64 whatever its size, such as a
  # cursor id sent back in getMore.
  class Int64
    def initialize(value)
      if value < -9223372036854775807 - 1 || value > 9223372036854775807
        raise RangeError, value.to_s + " is not a valid int64"
      end
      @value = value
    end

    def value
      @value
    end

    def to_i
      @value
    end

    def ==(other)
      other.is_a?(Int64) && other.value == @value
    end

    def eql?(other)
      self == other
    end

    def hash
      @value.hash
    end
  end

  class Binary
    # The subtype byte for each of the gem's type names. :user is 0x80;
    # a decoded subtype from 0x80 up reads as :user too.
    SUBTYPES = {
      generic: 0, function: 1, old: 2, uuid_old: 3, uuid: 4, md5: 5,
      ciphertext: 6, column: 7, sensitive: 8, vector: 9, user: 128
    }.freeze

    def initialize(data = "", type = :generic)
      unless SUBTYPES.key?(type)
        raise BSON::Error::InvalidBinaryType,
              ":" + type.to_s + " is not a valid binary type."
      end
      @data = data.b
      @type = type
    end

    def data
      @data
    end

    def type
      @type
    end

    def subtype
      SUBTYPES[@type]
    end

    def self.type_for(subtype)
      return :user if subtype >= 128
      SUBTYPES.each { |name, byte| return name if byte == subtype }
      raise BSON::Error::UnsupportedType, "Unknown binary subtype " + subtype.to_s
    end

    def ==(other)
      other.is_a?(Binary) && other.type == @type && other.data == @data
    end

    def eql?(other)
      self == other
    end

    def hash
      @data.hash
    end

    def inspect
      "<BSON::Binary:0x" + object_id.to_s(16) + " type=" + @type.to_s +
        " data=0x" + @data.byteslice(0, 8).unpack1("H*") + "...>"
    end
  end
end
