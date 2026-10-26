# Dual-runtime: SCRAM. The hashes, HMAC and PBKDF2 against published
# vectors (FIPS 180, RFC 4231, RFC 2202, RFC 6070), the whole exchanges
# from RFC 7677, RFC 5802 and MongoDB's auth spec, the secrets each
# mechanism stretches, and each check the gem makes on the server's
# messages. Then Connection#authenticate against a scripted server that
# does the server side of SCRAM: the mechanism it picks, the commands it
# sends, the third step, and each way a login fails. CRuby's output is
# the expectation.
require "mongo/connection"

def hx(s)
  s.unpack1("H*")
end

def unhx(h)
  [h].pack("H*")
end

def check(name, got, want)
  puts name + " " + (got == want).to_s + (got == want ? "" : " got=" + got)
end

def failure(label, e)
  puts label + ": " + e.class.to_s + " " + e.message
end

sha1 = Mongo::Scram::SHA1
sha256 = Mongo::Scram::SHA256
nul = [0].pack("C")

puts "-- primitives"
check "sha256 abc", hx(Mongo::Scram.digest(sha256, "abc")), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
check "sha1 abc", hx(Mongo::Scram.digest(sha1, "abc")), "a9993e364706816aba3e25717850c26c9cd0d89d"
check "sha256 with nul", hx(Mongo::Scram.digest(sha256, "a" + nul + "b")), "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138"
key = unhx("0b" * 20)
check "rfc4231 1", hx(Mongo::Scram.hmac(sha256, key, "Hi There")), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
check "rfc4231 2", hx(Mongo::Scram.hmac(sha256, "Jefe", "what do ya want for nothing?")), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
# A key longer than the block is hashed first.
check "rfc4231 6", hx(Mongo::Scram.hmac(sha256, unhx("aa" * 131), "Test Using Larger Than Block-Size Key - Hash Key First")),
      "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
check "rfc2202 1", hx(Mongo::Scram.hmac(sha1, key, "Hi There")), "b617318655057264e28bc0b6fb378c8ef146be00"
check "rfc2202 6", hx(Mongo::Scram.hmac(sha1, unhx("aa" * 80), "Test Using Larger Than Block-Size Key - Hash Key First")),
      "aa4ae5e15272d00e95705637ce8a3b55ed402112"
# A key that starts with a NUL. The expected value is from CRuby's
# libcrypto, not a published vector.
check "hmac nul key", hx(Mongo::Scram.hmac(sha256, nul + "key", "msg")), "30bca64089ec9063addcae1bf87de914b3f17389c3a1169a6d3fa9d6dd347230"
check "rfc6070 c=1", hx(Mongo::Scram.pbkdf2(sha1, "password", "salt", 1)), "0c60c80f961f0e71f3a9b524af6012062fe037a6"
check "rfc6070 c=2", hx(Mongo::Scram.pbkdf2(sha1, "password", "salt", 2)), "ea6c014dc72d6f8ccd1ed92ace1d41f0d8de8957"
check "rfc6070 c=4096", hx(Mongo::Scram.pbkdf2(sha1, "password", "salt", 4096)), "4b007901b765489abead49d926f721d065a429c1"
check "rfc6070 nul", hx(Mongo::Scram.pbkdf2(sha1, "pass" + nul + "word", "sa" + nul + "lt", 4096)).byteslice(0, 32), "56fa6aa75548099dcc37d7f03425e0c3"
check "pbkdf2 sha256 c=4096", hx(Mongo::Scram.pbkdf2(sha256, "password", "salt", 4096)), "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a"
check "xor", hx(Mongo::Scram.xor(unhx("ff00f0"), unhx("0f0fff"))), "f00f0f"
check "base64 nul round trip", hx(Mongo::Scram.unb64(Mongo::Scram.b64(nul + "x" + nul))), "007800"

puts "-- exchanges"
# RFC 7677 section 3, SCRAM-SHA-256.
s = Mongo::Scram.new(sha256, "user", Mongo::Scram.secret(sha256, "user", "pencil"), "rOprNGfwEbeRWgbNEkqO")
check "rfc7677 client first", s.client_first, "n,,n=user,r=rOprNGfwEbeRWgbNEkqO"
check "rfc7677 client final", s.client_final("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"),
      "c=biws,r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,p=dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ="
puts "rfc7677 before verify " + s.verified?.to_s
s.verify("v=6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=")
puts "rfc7677 verified " + s.verified?.to_s

# RFC 5802 section 5, SCRAM-SHA-1 over the plain password.
s = Mongo::Scram.new(sha1, "user", "pencil", "fyko+d2lbbFgONRv9qkxdawL")
check "rfc5802 client final", s.client_final("r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,s=QSXCR+Q6sek8bf92,i=4096"),
      "c=biws,r=fyko+d2lbbFgONRv9qkxdawL3rfcNHYJY1ZVvWVs7j,p=v0X8v3Bz2T0CJGbJQyF0X+HI4Ts="
s.verify("v=rmF9pqV8S7suAoZWja4dJRkFsKQ=")
puts "rfc5802 verified " + s.verified?.to_s

# MongoDB's auth spec, SCRAM-SHA-1 over the hex MD5 of user:mongo:pencil.
secret = Mongo::Scram.secret(sha1, "user", "pencil")
check "mongodb sha1 secret", secret, "1c33006ec1ffd90f9cadcbcc0e118200"
s = Mongo::Scram.new(sha1, "user", secret, "fyko+d2lbbFgONRv9qkxdawL")
check "mongodb sha1 client final",
      s.client_final("r=fyko+d2lbbFgONRv9qkxdawLHo+Vgk7qvUOKUwuWLIWg4l/9SraGMHEE,s=rQ9ZY3MntBeuP3E1TDVC4w==,i=10000"),
      "c=biws,r=fyko+d2lbbFgONRv9qkxdawLHo+Vgk7qvUOKUwuWLIWg4l/9SraGMHEE,p=MC2T8BvbmWRckDw8oWl5IVghwCY="
s.verify("v=UMWeI25JD1yNYZRMpZ4VHvhZ9e0=")
puts "mongodb sha1 verified " + s.verified?.to_s

puts "-- secrets and names"
check "sha256 secret is the password", Mongo::Scram.secret(sha256, "app", "s3cret pass ~!"), "s3cret pass ~!"
["café", "tab\there", "del" + [127].pack("C")].each do |pw|
  begin
    Mongo::Scram.secret(sha256, "app", pw)
    puts "sha256 " + pw.bytesize.to_s + " bytes: no error"
  rescue ArgumentError => e
    puts "sha256 " + pw.bytesize.to_s + " bytes: " + e.class.to_s + " " + e.message
  end
end
check "sha1 takes any password", Mongo::Scram.secret(sha1, "app", "café"), "388d6ef33efc63a4a923db7d797cbee6"
check "user escaping", Mongo::Scram.new(sha256, "a=b,c", "x", "n").client_first, "n,,n=a=3Db=2Cc,r=n"
n1 = Mongo::Scram.nonce
n2 = Mongo::Scram.nonce
puts "nonce " + n1.length.to_s + " chars, base64 of " + Mongo::Scram.unb64(n1).bytesize.to_s + " bytes, fresh " + (n1 != n2).to_s

puts "-- the server's first and final messages"
s = Mongo::Scram.new(sha256, "user", "pencil", "rOprNGfwEbeRWgbNEkqO")
bad = [
  ["few iterations", "r=rOprNGfwEbeRWgbNEkqOxyz,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4095"],
  ["foreign nonce", "r=someoneElse,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096"],
  ["no salt", "r=rOprNGfwEbeRWgbNEkqOxyz,i=4096"]
]
bad.each do |pair|
  begin
    s.client_final(pair[1])
    puts pair[0] + ": no error"
  rescue Mongo::Error => e
    failure(pair[0], e)
  rescue Mongo::Error::AuthError => e
    failure(pair[0], e)
  end
end
s.client_final("r=rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0,s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096")
s.verify("")
puts "no v: verified " + s.verified?.to_s
begin
  s.verify("v=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=")
rescue Mongo::Error::InvalidSignature => e
  failure("wrong v", e)
end

# The server side of SCRAM for one user, over Connection's transport
# duck. Each request it is written gets its reply queued, and read_some
# hands the replies back. mode makes it misbehave: "three steps" (done
# only after an empty third step), "wrong v", "no v", "never done".
class ScramServer
  SALT = "c2FsdHlzYWx0eXNhbHR5"

  def initialize(user, password, mechs, iterations, mode)
    @user = user
    @password = password
    @mechs = mechs
    @iterations = iterations
    @mode = mode
    @queue = []
    @requests = []
    @closes = 0
    @first_bare = ""
    @server_first = ""
    @mechanism = ""
  end

  def requests
    @requests
  end

  def closes
    @closes
  end

  def close
    @closes += 1
    nil
  end

  def peer_closed?
    false
  end

  def read_some(max)
    return "".b if @queue.length == 0
    @queue.shift
  end

  def write(bytes)
    p = Mongo::Wire::Parser.new
    p.feed(bytes)
    p.try_next
    doc = p.document
    @requests.push(doc)
    answer(p.request_id, respond(doc))
    nil
  end

  def answer(response_to, doc)
    op = Mongo::Wire.op_msg(500 + response_to, doc)
    @queue.push(op.byteslice(0, 8) + [response_to].pack("l<") + op.byteslice(12, op.bytesize - 12))
    nil
  end

  def fail(code, code_name, text)
    { "ok" => 0.0, "errmsg" => text, "code" => code, "codeName" => code_name }
  end

  def respond(doc)
    if doc.key?("hello")
      reply = { "isWritablePrimary" => true, "maxWireVersion" => 25, "ok" => 1.0 }
      if doc.key?("saslSupportedMechs") && doc["saslSupportedMechs"] == "admin." + @user
        reply["saslSupportedMechs"] = @mechs
      end
      return reply
    end
    return { "ok" => 1.0 } if doc.key?("ping")
    if doc.key?("saslStart")
      @mechanism = doc["mechanism"]
      first = doc["payload"].data
      @first_bare = first[3, first.length - 3]
      name = Mongo::Scram.attr(@first_bare, "n")
      if name != @user || doc["$db"] != "admin"
        return fail(18, "AuthenticationFailed", "Authentication failed.")
      end
      unless @mechs.include?(@mechanism)
        return fail(334, "MechanismUnavailable", "Unable to use " + @mechanism +
                    " based authentication for user without any " + @mechanism + " credentials registered")
      end
      @server_first = "r=" + Mongo::Scram.attr(@first_bare, "r") + "srvNonce,s=" + SALT + ",i=" + @iterations.to_s
      return { "conversationId" => 1, "done" => false, "payload" => BSON::Binary.new(@server_first), "ok" => 1.0 }
    end
    payload = doc["payload"].data
    if payload == ""
      return { "conversationId" => 1, "done" => @mode != "never done", "payload" => BSON::Binary.new(""), "ok" => 1.0 }
    end
    m = @mechanism
    salted = Mongo::Scram.pbkdf2(m, Mongo::Scram.secret(m, @user, @password), Mongo::Scram.unb64(SALT), @iterations)
    stored = Mongo::Scram.digest(m, Mongo::Scram.hmac(m, salted, "Client Key"))
    without_proof = payload[0, payload.index(",p=")]
    auth_message = @first_bare + "," + @server_first + "," + without_proof
    client_key = Mongo::Scram.xor(Mongo::Scram.unb64(Mongo::Scram.attr(payload, "p")),
                                  Mongo::Scram.hmac(m, stored, auth_message))
    if Mongo::Scram.digest(m, client_key) != stored
      return fail(18, "AuthenticationFailed", "Authentication failed.")
    end
    v = Mongo::Scram.b64(Mongo::Scram.hmac(m, Mongo::Scram.hmac(m, salted, "Server Key"), auth_message))
    v = "AAAAAAAAAAAAAAAAAAAAAAAAAAA=" if @mode == "wrong v"
    final = @mode == "no v" ? "" : "v=" + v
    { "conversationId" => 1, "done" => @mode == "" || @mode == "no v", "payload" => BSON::Binary.new(final), "ok" => 1.0 }
  end
end

def login(server, user, password, mechanism)
  c = Mongo::Connection.new(server, "db.example:27017")
  c.handshake("", "admin." + user)
  used = c.authenticate(user, password, "railyard", "admin", mechanism)
  steps = []
  server.requests.each do |r|
    steps.push(r.keys[0]) unless r.key?("hello")
  end
  puts "logged in with " + used + " in " + steps.join(",") + " open=" + (!c.closed?).to_s
  c
end

def refused(label, server, user, password, mechanism)
  c = Mongo::Connection.new(server, "db.example:27017")
  c.handshake("", "admin." + user)
  begin
    c.authenticate(user, password, "railyard", "admin", mechanism)
    puts label + ": no error"
  rescue Mongo::Auth::Unauthorized => e
    puts label + ": " + e.class.to_s + " " + e.message + " | code=" + e.code.inspect +
         " is an AuthError " + e.is_a?(Mongo::Error::AuthError).to_s + ", a Mongo::Error " + e.is_a?(Mongo::Error).to_s
  rescue Mongo::Error::InvalidSignature => e
    # The signature it expected depends on the random nonce.
    puts label + ": " + e.class.to_s + " " + e.message[0, e.message.index(" to match")] + " verifier=" + e.verifier
  rescue Mongo::Error => e
    failure(label, e)
  rescue Mongo::Error::AuthError => e
    failure(label, e)
  end
  puts "  closed=" + c.closed?.to_s + " transport closes=" + server.closes.to_s
end

puts "-- authenticate"
both = [sha256, sha1]
server = ScramServer.new("app", "s3cret pass", both, 15000, "")
login(server, "app", "s3cret pass", "")
start = server.requests[1]
puts "saslStart " + start.keys.join(",") + " mechanism=" + start["mechanism"] + " autoAuthorize=" + start["autoAuthorize"].to_s +
     " skipEmptyExchange=" + start["options"]["skipEmptyExchange"].to_s + " payload starts n,,n=app,r= " +
     start["payload"].data.start_with?("n,,n=app,r=").to_s
step = server.requests[2]
puts "saslContinue " + step.keys.join(",") + " conversationId=" + step["conversationId"].to_s
login(ScramServer.new("legacy", "older pass", [sha1], 10000, ""), "legacy", "older pass", "")
login(ScramServer.new("app", "s3cret pass", both, 4096, ""), "app", "s3cret pass", sha1)
login(ScramServer.new("app", "s3cret pass", both, 4096, "three steps"), "app", "s3cret pass", sha256)
login(ScramServer.new("app", "s3cret pass", both, 4096, ""), "app", "s3cret pass", "")
c = login(ScramServer.new("app", "s3cret pass", both, 4096, ""), "app", "s3cret pass", "")
puts "a command after it ok=" + c.command({ "ping" => 1, "$db" => "admin" })["ok"].to_s

puts "-- refused"
refused("wrong password", ScramServer.new("app", "s3cret pass", both, 4096, ""), "app", "wrong", "")
refused("wrong password, asked for SCRAM-SHA-1", ScramServer.new("app", "s3cret pass", both, 4096, ""), "app", "wrong", sha1)
refused("unknown user", ScramServer.new("app", "s3cret pass", both, 4096, ""), "nobody", "x", "")
refused("SCRAM-SHA-256 for a SHA-1 user", ScramServer.new("legacy", "older pass", [sha1], 4096, ""), "legacy", "older pass", sha256)
refused("wrong server signature", ScramServer.new("app", "s3cret pass", both, 4096, "wrong v"), "app", "s3cret pass", "")
refused("no server signature", ScramServer.new("app", "s3cret pass", both, 4096, "no v"), "app", "s3cret pass", "")
refused("never done", ScramServer.new("app", "s3cret pass", both, 4096, "never done"), "app", "s3cret pass", "")
refused("few iterations", ScramServer.new("app", "s3cret pass", both, 1000, ""), "app", "s3cret pass", "")
