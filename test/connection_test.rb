# Dual-runtime: Mongo::Connection over a scripted transport. The
# handshake and what it keeps, commands with and without a kind 1
# section, each kind of failed reply and the gem's message for it, and
# each way the connection breaks: a reply to another request, the server
# closing mid-reply, a read timeout, a malformed frame. CRuby's output is
# the expectation.
require "mongo/connection"

# Serves canned reply bytes a chunk at a time, records each request, and
# when the chunks run out answers "" (the server closed) or, if told to,
# times out as Mongo::Transport does.
class ScriptedTransport
  def initialize(chunks, time_out = false)
    @chunks = chunks
    @i = 0
    @time_out = time_out
    @written = []
    @closes = 0
  end

  def write(bytes)
    @written.push(bytes)
    nil
  end

  def read_some(max)
    if @i >= @chunks.length
      raise Mongo::Error::SocketTimeoutError, "Took more than 1.0 seconds to receive data" if @time_out
      return "".b
    end
    chunk = @chunks[@i]
    @i += 1
    chunk
  end

  # Closed once every scripted reply has been read, unless it is
  # scripted to time out instead.
  def peer_closed?
    @i >= @chunks.length && !@time_out
  end

  def close
    @closes += 1
    nil
  end

  def written
    @written
  end

  def closes
    @closes
  end
end

def le32(n)
  [n].pack("l<")
end

# A reply from the server to request response_to.
def reply(response_to, doc)
  op = Mongo::Wire.op_msg(900 + response_to, doc)
  op.byteslice(0, 8) + le32(response_to) + op.byteslice(12, op.bytesize - 12)
end

# A request the connection wrote, cut and decoded as the server would.
def request(bytes)
  p = Mongo::Wire::Parser.new
  p.feed(bytes)
  p.try_next
  p
end

def failure(label, e)
  line = label + ": " + e.class.to_s + " " + e.message
  if e.is_a?(Mongo::Error::OperationFailure)
    line = line + " | code=" + e.code.inspect + " code_name=" + e.code_name.inspect +
           " server_message=" + e.server_message.inspect
  end
  puts line
end

HELLO = { "isWritablePrimary" => true, "maxBsonObjectSize" => 16777216,
          "maxMessageSizeBytes" => 48000000, "maxWriteBatchSize" => 100000,
          "maxWireVersion" => 25, "minWireVersion" => 0, "ok" => 1.0 }

def connected(chunks)
  t = ScriptedTransport.new([reply(1, HELLO)] + chunks)
  c = Mongo::Connection.new(t, "db.example:27017")
  c.handshake
  [t, c]
end

puts "-- hello"
client = { "driver" => { "name" => "spinel-mongo", "version" => "0.0.1" },
           "os" => { "type" => "linux", "name" => "linux", "architecture" => "x86_64" },
           "platform" => "Spinel (Ruby 4.0.7), x86_64-linux" }
puts "hello bytes " + Mongo::Wire.op_msg(1, Mongo::Connection.hello_command(client, "admin.app")).unpack1("H*")
doc = Mongo::Connection.client_document("railyard")
puts "client keys " + doc.keys.join(",") + " driver=" + doc["driver"]["name"] + " " + doc["driver"]["version"] +
     " app=" + doc["application"]["name"]
expected = RUBY_ENGINE == "spinel" ? "Spinel (Ruby " : "Ruby "
puts "platform names the runtime " + doc["platform"].start_with?(expected).to_s +
     " os=" + doc["os"].keys.join(",") + " no app " + Mongo::Connection.client_document("").key?("application").to_s

t = ScriptedTransport.new([reply(1, HELLO)])
c = Mongo::Connection.new(t, "db.example:27017")
r = c.handshake("railyard", "admin.app")
sent = request(t.written[0]).document
puts "sent " + sent.keys.join(",") + " sasl=" + sent["saslSupportedMechs"] + " app=" + sent["client"]["application"]["name"]
puts "kept writable=" + c.hello["isWritablePrimary"].to_s + " wire=" + c.max_wire_version.to_s +
     " bson=" + c.max_bson_object_size.to_s + " msg=" + c.max_message_size.to_s +
     " batch=" + c.max_write_batch_size.to_s + " same=" + (r == c.hello).to_s

t = ScriptedTransport.new([reply(1, { "isWritablePrimary" => true, "maxWireVersion" => 21, "ok" => 1.0 })])
c = Mongo::Connection.new(t, "db.example:27017")
c.handshake
puts "defaults bson=" + c.max_bson_object_size.to_s + " msg=" + c.max_message_size.to_s + " batch=" + c.max_write_batch_size.to_s

begin
  t = ScriptedTransport.new([reply(1, { "ismaster" => true, "maxWireVersion" => 13, "ok" => 1.0 })])
  c = Mongo::Connection.new(t, "db.example:27017")
  c.handshake
  puts "old server: no error"
rescue Mongo::Error => e
  failure("old server", e)
  puts "closed=" + c.closed?.to_s + " transport closes=" + t.closes.to_s
end

begin
  t = ScriptedTransport.new([])
  c = Mongo::Connection.new(t, "db.example:27017")
  c.handshake
  puts "dropped at hello: no error"
rescue Mongo::Error => e
  failure("dropped at hello", e)
end

begin
  t = ScriptedTransport.new([], true)
  c = Mongo::Connection.new(t, "db.example:27017")
  c.handshake
  puts "silent at hello: no error"
rescue Mongo::Error => e
  failure("silent at hello", e)
end

puts "-- commands"
ping = reply(2, { "ok" => 1.0 })
pieces = []
i = 0
while i < ping.bytesize
  pieces.push(ping.byteslice(i, 3))
  i += 3
end
docs = [{ "_id" => 1, "name" => "Big Boy" }, { "_id" => 2, "name" => "Mallard" }]
t, c = connected(pieces + [reply(3, { "n" => 2, "ok" => 1.0 })])
puts "ping in 3-byte reads " + c.command({ "ping" => 1, "$db" => "admin" }).keys.join(",")
r = c.command_seq({ "insert" => "locomotives", "ordered" => true, "$db" => "t" }, "documents", docs)
w = request(t.written[2])
puts "insert n=" + r["n"].to_s + " request id=" + w.request_id.to_s + " seq=" + w.seq_id + ":" + w.seq_docs.length.to_s +
     " body=" + w.document.keys.join(",")

puts "-- failed replies"
dup = "E11000 duplicate key error collection: t.locomotives index: _id_ dup key: { _id: 1 }"
dup2 = "E11000 duplicate key error collection: t.locomotives index: _id_ dup key: { _id: 2 }"
cases = [
  ["ok 0", { "ok" => 0.0, "errmsg" => "no such command: 'nope'", "code" => 59, "codeName" => "CommandNotFound" }],
  ["ok 0 without a code", { "ok" => 0.0, "errmsg" => "something broke" }],
  ["write error", { "n" => 0, "writeErrors" => [{ "index" => 0, "code" => 11000, "errmsg" => dup }], "ok" => 1.0 }],
  ["write errors with one code", { "n" => 0, "writeErrors" => [{ "index" => 0, "code" => 11000, "errmsg" => dup },
                                                               { "index" => 1, "code" => 11000, "errmsg" => dup2 }], "ok" => 1.0 }],
  ["write errors with two codes", { "n" => 0, "writeErrors" => [{ "index" => 0, "code" => 11000, "errmsg" => dup },
                                                                { "index" => 1, "code" => 121, "errmsg" => "Document failed validation" }], "ok" => 1.0 }],
  ["write concern error", { "n" => 1, "writeConcernError" => { "code" => 64, "codeName" => "WriteConcernFailed",
                                                               "errmsg" => "waiting for replication timed out" }, "ok" => 1.0 }],
  ["one-character errmsg", { "ok" => 0.0, "errmsg" => "x", "writeConcernError" => { "errmsg" => "y" } }]
]
cases.each do |pair|
  t, c = connected([reply(2, pair[1])])
  begin
    c.command({ "insert" => "locomotives", "$db" => "t" })
    puts pair[0] + ": no error"
  rescue Mongo::Error => e
    failure(pair[0], e)
    puts "  open=" + (!c.closed?).to_s
  end
end

bulk = { "n" => 1, "writeErrors" => [{ "index" => 0, "code" => 11000, "errmsg" => dup },
                                     { "index" => 2, "code" => 11000, "errmsg" => dup2 }], "ok" => 1.0 }
t, c = connected([reply(2, bulk), reply(3, { "n" => 3, "ok" => 1.0 }), reply(4, { "ok" => 0.0, "errmsg" => "bad", "code" => 2, "codeName" => "BadValue" })])
begin
  c.write_seq({ "insert" => "locomotives", "ordered" => false, "$db" => "t" }, "documents", docs)
  puts "bulk: no error"
rescue Mongo::Error::BulkWriteError => e
  failure("bulk", e)
  puts "  result n=" + e.result["n"].to_s + " errors=" + e.result["writeErrors"].length.to_s
end
puts "bulk clean n=" + c.write_seq({ "insert" => "locomotives", "$db" => "t" }, "documents", docs)["n"].to_s
begin
  c.write_seq({ "insert" => "locomotives", "$db" => "t" }, "documents", docs)
rescue Mongo::Error => e
  failure("bulk ok 0", e)
end
many = []
i = 0
while i < 12
  many.push({ "index" => i, "code" => 11000, "errmsg" => "dup " + i.to_s })
  i += 1
end
puts "twelve: " + Mongo::Error::BulkWriteError.new({ "writeErrors" => many }).message
puts "none: " + Mongo::Error::BulkWriteError.new({ "n" => 0 }).message

puts "-- broken connections"
t, c = connected([reply(7, { "ok" => 1.0 })])
begin
  c.command({ "ping" => 1, "$db" => "admin" })
  puts "mismatch: no error"
rescue Mongo::Error => e
  failure("mismatch", e)
end
puts "closed=" + c.closed?.to_s + " transport closes=" + t.closes.to_s
begin
  c.command({ "ping" => 1, "$db" => "admin" })
rescue Mongo::Error => e
  failure("after close", e)
end
puts "requests written " + t.written.length.to_s

half = reply(2, { "ok" => 1.0 })
t, c = connected([half.byteslice(0, 10)])
begin
  c.command({ "ping" => 1, "$db" => "admin" })
rescue Mongo::Error => e
  failure("closed mid-reply", e)
end
puts "closed=" + c.closed?.to_s

t = ScriptedTransport.new([reply(1, HELLO)], true)
c = Mongo::Connection.new(t, "db.example:27017")
c.handshake
begin
  c.command({ "ping" => 1, "$db" => "admin" })
rescue Mongo::Error => e
  failure("timeout", e)
end
puts "closed=" + c.closed?.to_s + " is a TimeoutError " + Mongo::Error::SocketTimeoutError.new("x").is_a?(Mongo::Error::TimeoutError).to_s

more = reply(2, { "ok" => 1.0 })
more = more.byteslice(0, 16) + [2].pack("V") + more.byteslice(20, more.bytesize - 20)
t, c = connected([more])
begin
  c.command({ "ping" => 1, "$db" => "admin" })
rescue Mongo::Error => e
  failure("moreToCome", e)
end
puts "closed=" + c.closed?.to_s

c.close
c.close
puts "close twice: transport closes=" + t.closes.to_s

puts "-- stale connections"
t, c = connected([reply(2, { "ok" => 1.0 })])
puts "a reply still to come: stale=" + c.stale?.to_s
c.command({ "ping" => 1, "$db" => "admin" })
puts "the server's end closed: stale=" + c.stale?.to_s + " closed=" + c.closed?.to_s
t, c = connected([])
c.close
puts "closed by the client: stale=" + c.stale?.to_s
