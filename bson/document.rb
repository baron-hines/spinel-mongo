# BSON::Document is what the decoder returns: a Hash with String keys
# that also answers Symbol keys, as the gem's does. Encoding takes any
# Hash, so callers never have to build one.
module BSON
  class Document < Hash
    def initialize(hash = nil)
      super()
      hash.each { |k, v| self[k] = v } unless hash.nil?
    end

    def [](key)
      super(key.is_a?(Symbol) ? key.to_s : key)
    end

    def []=(key, value)
      super(key.is_a?(Symbol) ? key.to_s : key, value)
    end

    def key?(key)
      super(key.is_a?(Symbol) ? key.to_s : key)
    end

    def has_key?(key)
      key?(key)
    end

    def include?(key)
      key?(key)
    end

    def fetch(key, *rest)
      super(key.is_a?(Symbol) ? key.to_s : key, *rest)
    end

    def delete(key)
      super(key.is_a?(Symbol) ? key.to_s : key)
    end

    def dig(key, *rest)
      v = self[key]
      return v if rest.empty? || v.nil?
      v.dig(*rest)
    end
  end
end
