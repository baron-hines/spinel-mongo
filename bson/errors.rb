# The bson gem's error classes that spinel-mongo raises. Like the gem,
# a NUL byte in a key raises ArgumentError, and reading past the end of
# the input raises RangeError.
module BSON
  class Error < StandardError
    # A string or document whose bytes don't match its declared length.
    class BSONDecodeError < Error
    end

    # A BSON type byte this driver doesn't decode.
    class UnsupportedType < Error
    end

    # A Ruby value with no BSON type.
    class UnserializableClass < Error
    end

    class InvalidObjectId < Error
    end

    class InvalidBinaryType < Error
    end

    class InvalidKey < Error
    end
  end
end
