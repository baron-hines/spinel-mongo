# BSON::ObjectId: 12 bytes, generated as the BSON spec gives it.
require "securerandom"

module BSON
  class ObjectId
    # 4 bytes of big-endian seconds, 5 random bytes fixed per process
    # (drawn again when Process.pid changes, so a forked child never
    # repeats its parent's ids), and a 3-byte big-endian counter that
    # starts at a random value and wraps at 2**24. A Mutex keeps threads
    # from taking the same count: Spinel's threads run in parallel, with
    # no lock around a read and a write of @counter.
    class Generator
      def initialize
        @pid = -1
        @random = "".b
        @counter = 0
        @lock = Mutex.new
      end

      def next_bytes(seconds)
        @lock.lock
        begin
          if @pid != Process.pid
            @pid = Process.pid
            @random = SecureRandom.random_bytes(5).b
            @counter = SecureRandom.random_number(16777216)
          end
          c = @counter
          @counter = (@counter + 1) % 16777216
          random = @random
        ensure
          @lock.unlock
        end
        [seconds].pack("N") + random + [(c >> 16) & 0xff, (c >> 8) & 0xff, c & 0xff].pack("C*")
      end

      # Tests set the counter to see it wrap.
      def counter=(n)
        @counter = n
      end

      def counter
        @counter
      end
    end

    GENERATOR = Generator.new

    # With no argument, a new id from the generator. The gem's own
    # constructors for an existing id are from_string and from_data.
    def initialize(data = nil)
      @data = data.nil? ? GENERATOR.next_bytes(Time.now.to_i) : data.b
    end

    def self.from_data(data)
      new(data)
    end

    def self.from_string(string)
      unless legal?(string)
        raise BSON::Error::InvalidObjectId, "'" + string.to_s + "' is an invalid ObjectId."
      end
      new([string].pack("H*"))
    end

    # True for 24 hex digits, either case.
    def self.legal?(string)
      return false unless string.is_a?(String) && string.bytesize == 24
      i = 0
      while i < 24
        c = string.getbyte(i)
        hex = (c >= 48 && c <= 57) || (c >= 97 && c <= 102) || (c >= 65 && c <= 70)
        return false unless hex
        i += 1
      end
      true
    end

    def data
      @data
    end

    def to_s
      @data.unpack1("H*")
    end

    def to_str
      to_s
    end

    def inspect
      "BSON::ObjectId('" + to_s + "')"
    end

    def generation_time
      Time.at(@data.byteslice(0, 4).unpack1("N")).utc
    end

    def ==(other)
      other.is_a?(ObjectId) && other.data == @data
    end

    def eql?(other)
      self == other
    end

    def hash
      @data.hash
    end

    def <=>(other)
      @data <=> other.data
    end
  end
end
