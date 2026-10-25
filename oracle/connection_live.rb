# Twin of test/connection_live_test.rb through the mongo gem. The gem's
# OperationFailure messages end with where the error happened, such as
# " (on 127.0.0.1:27217)"; this driver's don't (see the README's ledger),
# so that note is cut before printing. The gem has no bare connection, so
# a client stands in for each one the test opens.
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

def strip_note(message)
  message.sub(/ \(on [^)]*\)\z/, "")
end

def now
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

port = ARGV.length > 0 ? ARGV[0].to_i : 27217
client = Mongo::Client.new(["127.0.0.1:#{port}"], database: "connection_live", direct_connection: true)
h = client.use("admin").database.command(hello: 1).first
puts "hello ok=" + h["ok"].to_s + " writable=" + h["isWritablePrimary"].to_s +
     " wire>=17=" + (h["maxWireVersion"] >= 17).to_s + " bson=" + h["maxBsonObjectSize"].to_s +
     " msg=" + h["maxMessageSizeBytes"].to_s + " batch=" + h["maxWriteBatchSize"].to_s
puts "ping ok=" + client.use("admin").database.command(ping: 1).first["ok"].to_s

begin
  client.database.command(nope: 1)
  puts "unknown: no error"
rescue Mongo::Error::OperationFailure => e
  puts "unknown: " + e.class.to_s + " " + strip_note(e.message) + " code=" + e.code.to_s + " code_name=" + e.code_name.to_s
end

coll = client[:locomotives]
coll.drop
r = coll.insert_many([{ "_id" => 1, "name" => "Big Boy" }, { "_id" => 2, "name" => "Mallard" }])
puts "insert n=" + r.inserted_count.to_s

begin
  coll.insert_one({ "_id" => 1, "name" => "Big Boy again" })
  puts "duplicate: no error"
rescue Mongo::Error::OperationFailure => e
  puts "duplicate: " + e.class.to_s + " " + strip_note(e.message) + " code=" + e.code.to_s + " code_name=" + e.code_name.inspect
end

batch = [{ "_id" => 1, "name" => "Big Boy" }, { "_id" => 3, "name" => "Flying Scotsman" },
         { "_id" => 2, "name" => "Mallard" }, { "_id" => 4, "name" => "Rocket" }]
begin
  coll.insert_many(batch, ordered: false)
  puts "bulk: no error"
rescue Mongo::Error::BulkWriteError => e
  idx = e.result["writeErrors"].map { |w| w["index"].to_s }
  puts "bulk: " + e.class.to_s + " " + e.message + " indexes=" + idx.join(",")
end

puts "find " + coll.find.sort("_id" => 1).map { |d| d["name"] }.join(",")

slow = Mongo::Client.new(["127.0.0.1:#{port}"], database: "admin", direct_connection: true, socket_timeout: 1)
t0 = now
begin
  slow.database.command(sleep: 1, secs: 3, lock: "none")
  puts "sleep: no error"
rescue Mongo::Error::SocketTimeoutError => e
  took = now - t0
  puts "sleep past socket_timeout 1: " + e.class.to_s + " after 1s=" + (took >= 0.9 && took < 2.0).to_s
end
fresh = Mongo::Client.new(["127.0.0.1:#{port}"], database: "admin", direct_connection: true)
puts "a new connection pings ok=" + fresh.database.command(ping: 1).first["ok"].to_s

begin
  Mongo::Client.new(["127.0.0.1:#{port + 1}"], database: "admin", direct_connection: true,
                    server_selection_timeout: 1, connect_timeout: 1).database.command(ping: 1)
  puts "refused: no error"
rescue Mongo::Error::NoServerAvailable => e
  puts "refused: " + e.class.to_s
end
