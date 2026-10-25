# Live: a connection to a real mongod. The handshake and its limits,
# ping, each kind of failed reply (an unknown command, a duplicate key, a
# bulk write with two), a read back, a command that runs past
# socket_timeout, and a refused connect. Spinel-only (the committed
# .expected keeps spin test from running it under CRuby);
# oracle/connection_live.rb runs the same flow through the mongo gem.
require "mongo"
require_relative "support/live_mongod"

PORT = 27317

live_mongod_start("connection", PORT)
c = live_connect(PORT, nil)
h = c.hello
puts "hello ok=" + h["ok"].to_s + " writable=" + h["isWritablePrimary"].to_s +
     " wire>=17=" + (c.max_wire_version >= 17).to_s + " bson=" + c.max_bson_object_size.to_s +
     " msg=" + c.max_message_size.to_s + " batch=" + c.max_write_batch_size.to_s
puts "ping ok=" + c.command({ "ping" => 1, "$db" => "admin" })["ok"].to_s

begin
  c.command({ "nope" => 1, "$db" => "connection_live" })
  puts "unknown: no error"
rescue Mongo::Error::OperationFailure => e
  puts "unknown: " + e.class.to_s + " " + e.message + " code=" + e.code.to_s + " code_name=" + e.code_name.to_s
end

c.command({ "drop" => "locomotives", "$db" => "connection_live" })
docs = [{ "_id" => 1, "name" => "Big Boy" }, { "_id" => 2, "name" => "Mallard" }]
r = c.command_seq({ "insert" => "locomotives", "ordered" => true, "$db" => "connection_live" }, "documents", docs)
puts "insert n=" + r["n"].to_s

begin
  c.command_seq({ "insert" => "locomotives", "ordered" => true, "$db" => "connection_live" },
                "documents", [{ "_id" => 1, "name" => "Big Boy again" }])
  puts "duplicate: no error"
rescue Mongo::Error::OperationFailure => e
  puts "duplicate: " + e.class.to_s + " " + e.message + " code=" + e.code.to_s + " code_name=" + e.code_name.inspect
end

batch = [{ "_id" => 1, "name" => "Big Boy" }, { "_id" => 3, "name" => "Flying Scotsman" },
         { "_id" => 2, "name" => "Mallard" }, { "_id" => 4, "name" => "Rocket" }]
begin
  c.write_seq({ "insert" => "locomotives", "ordered" => false, "$db" => "connection_live" }, "documents", batch)
  puts "bulk: no error"
rescue Mongo::Error::BulkWriteError => e
  idx = []
  e.result["writeErrors"].each { |w| idx.push(w["index"].to_s) }
  puts "bulk: " + e.class.to_s + " " + e.message + " indexes=" + idx.join(",")
end

r = c.command({ "find" => "locomotives", "filter" => {}, "sort" => { "_id" => 1 }, "$db" => "connection_live" })
names = []
r["cursor"]["firstBatch"].each { |d| names.push(d["name"]) }
puts "find " + names.join(",")

slow = live_connect(PORT, 1.0)
t0 = live_now
begin
  slow.command({ "sleep" => 1, "secs" => 3, "lock" => "none", "$db" => "admin" })
  puts "sleep: no error"
rescue Mongo::Error::SocketTimeoutError => e
  took = live_now - t0
  puts "sleep past socket_timeout 1: " + e.class.to_s + " after 1s=" + (took >= 0.9 && took < 2.0).to_s
end
puts "a new connection pings ok=" + live_connect(PORT, nil).command({ "ping" => 1, "$db" => "admin" })["ok"].to_s

begin
  live_connect(PORT + 1, nil)
  puts "refused: no error"
rescue Mongo::Error::NoServerAvailable => e
  puts "refused: " + e.class.to_s
end

c.close
live_mongod_stop("connection")
