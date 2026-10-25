# SCRAM (RFC 5802, RFC 7677) with the two mechanisms MongoDB has,
# SCRAM-SHA-256 and SCRAM-SHA-1. A Mongo::Scram is the client side of one
# conversation: client_first, then client_final from the server's first
# message, then verify on its final one. Connection#authenticate carries
# the messages; nothing here touches a socket.
#
# The hashes come from `require "digest"`: on Spinel the bundled package,
# which binds the runtime's own crypto and links nothing extra, and under
# CRuby its digest extension. HMAC and PBKDF2 are written here over them,
# so this file runs under both runtimes. The nonce is `securerandom`'s,
# from the OS on both.
require "digest"
require "securerandom"
require "mongo/errors"

module Mongo
  class Scram
    SHA1 = "SCRAM-SHA-1"
    SHA256 = "SCRAM-SHA-256"

    # The gem's floor: a server asking for fewer rounds is refused.
    MIN_ITERATIONS = 4096

    # The block size of SHA-1 and SHA-256, which HMAC pads its key to.
    BLOCK = 64

    def self.digest(mechanism, data)
      mechanism == SHA1 ? Digest::SHA1.digest(data) : Digest::SHA256.digest(data)
    end

    # HMAC's two padded keys: key XOR ipad and key XOR opad.
    def self.pads(mechanism, key)
      key = Scram.digest(mechanism, key) if key.bytesize > BLOCK
      inner = []
      outer = []
      i = 0
      while i < BLOCK
        b = i < key.bytesize ? key.getbyte(i) : 0
        inner.push(b ^ 0x36)
        outer.push(b ^ 0x5c)
        i += 1
      end
      [inner.pack("C*"), outer.pack("C*")]
    end

    def self.hmac(mechanism, key, data)
      pad = Scram.pads(mechanism, key)
      Scram.digest(mechanism, pad[1] + Scram.digest(mechanism, pad[0] + data.b))
    end

    # PBKDF2 with HMAC, one block long: all SCRAM needs. The padded keys
    # are made once, not once a round.
    def self.pbkdf2(mechanism, password, salt, iterations)
      pad = Scram.pads(mechanism, password.b)
      u = Scram.digest(mechanism, pad[1] + Scram.digest(mechanism, pad[0] + salt.b + [1].pack("N")))
      out = u.bytes
      i = 1
      while i < iterations
        u = Scram.digest(mechanism, pad[1] + Scram.digest(mechanism, pad[0] + u))
        j = 0
        while j < out.length
          out[j] = out[j] ^ u.getbyte(j)
          j += 1
        end
        i += 1
      end
      out.pack("C*")
    end

    def self.xor(a, b)
      out = []
      i = 0
      while i < a.bytesize
        out.push(a.getbyte(i) ^ b.getbyte(i))
        i += 1
      end
      out.pack("C*")
    end

    def self.b64(bytes)
      [bytes].pack("m0")
    end

    def self.unb64(text)
      text.unpack1("m").b
    end

    # What PBKDF2 stretches. For SCRAM-SHA-1, MongoDB's hex MD5 of
    # "user:mongo:password". For SCRAM-SHA-256, the password after
    # SASLprep, which leaves printable ASCII as it is; anything else would
    # need SASLprep's Unicode tables, which this driver doesn't carry, so
    # it raises ArgumentError.
    def self.secret(mechanism, user, password)
      return Digest::MD5.hexdigest(user + ":mongo:" + password) if mechanism == SHA1
      i = 0
      while i < password.bytesize
        b = password.getbyte(i)
        if b < 0x20 || b > 0x7e
          raise ArgumentError, "SCRAM-SHA-256 passwords must be printable ASCII in spinel-mongo, " \
                               "which doesn't implement SASLprep for other characters"
        end
        i += 1
      end
      password
    end

    # A user name in a SCRAM message: "=" and "," escaped.
    def self.encode_name(user)
      user.gsub("=", "=3D").gsub(",", "=2C")
    end

    # A client nonce as the gem makes one: 16 random bytes, base64.
    def self.nonce
      SecureRandom.base64
    end

    # The value of "x=" in a SCRAM message, or "" when it has none.
    def self.attr(message, name)
      message.split(",").each do |part|
        return part[2, part.length - 2] if part.start_with?(name + "=")
      end
      ""
    end

    def initialize(mechanism, user, secret, nonce)
      @mechanism = mechanism
      @secret = secret
      @nonce = nonce
      @first_bare = "n=" + Scram.encode_name(user) + ",r=" + nonce
      @server_signature = ""
      @verified = false
    end

    def mechanism
      @mechanism
    end

    # The saslStart payload.
    def client_first
      "n,," + @first_bare
    end

    # The saslContinue payload answering the server's first message.
    # Raises InsufficientIterationCount for fewer than 4096 rounds and
    # InvalidNonce for a nonce that doesn't extend the client's, as the
    # gem does, in that order.
    def client_final(server_first)
      rnonce = Scram.attr(server_first, "r")
      salt = Scram.attr(server_first, "s")
      count = Scram.attr(server_first, "i")
      if rnonce == "" || salt == "" || count == ""
        raise Mongo::Error::InvalidServerAuthResponse, "Payload malformed: missing key"
      end
      iterations = count.to_i
      if iterations < MIN_ITERATIONS
        raise Mongo::Error::InsufficientIterationCount,
              Mongo::Error::InsufficientIterationCount.message(MIN_ITERATIONS, iterations)
      end
      raise Mongo::Error::InvalidNonce.new(@nonce, rnonce) unless rnonce.start_with?(@nonce)
      salted = Scram.pbkdf2(@mechanism, @secret, Scram.unb64(salt), iterations)
      client_key = Scram.hmac(@mechanism, salted, "Client Key")
      stored_key = Scram.digest(@mechanism, client_key)
      without_proof = "c=biws,r=" + rnonce
      auth_message = @first_bare + "," + server_first + "," + without_proof
      proof = Scram.xor(client_key, Scram.hmac(@mechanism, stored_key, auth_message))
      server_key = Scram.hmac(@mechanism, salted, "Server Key")
      @server_signature = Scram.b64(Scram.hmac(@mechanism, server_key, auth_message))
      without_proof + ",p=" + Scram.b64(proof)
    end

    # Checks the server's signature when its message has one (v=), as the
    # gem does; raises InvalidSignature if it is wrong.
    def verify(server_final)
      v = Scram.attr(server_final, "v")
      return nil if v == ""
      raise Mongo::Error::InvalidSignature.new(v, @server_signature) unless v == @server_signature
      @verified = true
      nil
    end

    # Whether the server has proved it knows the password.
    def verified?
      @verified
    end
  end
end
