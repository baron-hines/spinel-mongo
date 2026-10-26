# Dual-runtime: Mongo::Client, Database, Collection, View and Cursor
# against a pretend mongod (test/support/fake_mongod.rb) with small
# limits. The commands each method sends, the gem's results, cursors
# with getMore and killCursors (a limit reached, a block that breaks
# out), insert_many split by maxWriteBatchSize and maxMessageSizeBytes,
# documents over maxBsonObjectSize refused before sending, write errors,
# and a connection that breaks and is opened again. CRuby's output is the
# expectation.
require "mongo/client"
require_relative "support/fake_mongod"

# The mongod the next client connects to.
class FakeHub
  def initialize
    @mongod = FakeMongod.new(16 * 1024 * 1024, 48_000_000, 100_000)
  end

  def mongod
    @mongod
  end

  def mongod=(m)
    @mongod = m
  end
end

HUB = FakeHub.new

module Mongo
  class Client
    def default_connector
      FakeConnector.new(HUB.mongod)
    end
  end
end

def show_log(m)
  m.log.each { |line| puts "  > " + line }
  m.log.clear
end

def failure(label, e)
  puts label + ": " + e.class.to_s + " " + e.message
end

puts "-- client"
m = FakeMongod.new(16 * 1024 * 1024, 48_000_000, 100_000)
HUB.mongod = m
client = Mongo::Client.new(["db.example:27018"], database: "railyard", connect_timeout: 2, socket_timeout: 1.5,
                                                 direct_connection: true)
puts "nothing opened yet: " + m.opens.length.to_s
db = client.database
puts "database " + db.name + " collection " + client[:locomotives].namespace + " " + db["tenders"].name
r = db.command(ping: 1)
puts "command " + r.class.to_s + " ok?=" + r.ok?.to_s + " first=" + r.first["ok"].to_s + " documents=" + r.documents.length.to_s
puts "opened " + m.opens.join("; ")
other = client.use(:depot)
puts "use " + other.database.name + " " + client.database.name
other.database.command(ping: 1)
puts "use shares the connection: opens=" + m.opens.length.to_s
show_log(m)
puts "collection_names " + db.collection_names.join(",")
show_log(m)
puts "default port " + Mongo::Client.open_server("h", {}, "admin", FakeConnector.new(m)).address +
     " ipv6 " + Mongo::Client.open_server("[::1]:27019", {}, "admin", FakeConnector.new(m)).address
[["two hosts", ["a:1", "b:2"], :scram], ["auth_mech", ["a:1"], :plain]].each do |c|
  begin
    Mongo::Client.new(c[1], auth_mech: c[2])
    puts c[0] + ": no error"
  rescue ArgumentError => e
    failure(c[0], e)
  rescue Mongo::Auth::InvalidMechanism => e
    failure(c[0], e)
  end
end

puts "-- writes"
coll = client[:locomotives]
doc = { "name" => "Big Boy", "wheels" => 24 }
r = coll.insert_one(doc)
puts "insert_one " + r.class.to_s + " n=" + r.n.to_s + " inserted_id is ObjectId=" + r.inserted_id.is_a?(BSON::ObjectId).to_s +
     " ids=" + r.inserted_ids.length.to_s + " caller's hash keys=" + doc.keys.join(",")
puts "stored " + m.docs[0].keys.join(",") + " same id=" + (m.docs[0]["_id"] == r.inserted_id).to_s
r = coll.insert_one({ name: "Mallard", _id: 7 })
puts "insert_one with a Symbol _id key: inserted_id=" + r.inserted_id.to_s + " stored " + m.docs[1].keys.join(",")
show_log(m)
docs = []
i = 0
while i < 5
  docs.push({ "_id" => 10 + i, "wheels" => i % 2 })
  i += 1
end
r = coll.insert_many(docs)
puts "insert_many " + r.class.to_s + " inserted_count=" + r.inserted_count.to_s + " ids=" + r.inserted_ids.inspect +
     " matched_count=" + r.matched_count.inspect
show_log(m)
r = coll.update_one({ "wheels" => 1 }, { "$set" => { "x" => 1 } })
puts "update_one " + r.class.to_s + " matched=" + r.matched_count.to_s + " modified=" + r.modified_count.to_s +
     " upserted_id=" + r.upserted_id.inspect + " upserted_count=" + r.upserted_count.to_s
r = coll.update_many({ "wheels" => 1 }, { "$set" => { "x" => 2 } })
puts "update_many matched=" + r.matched_count.to_s
r = coll.update_one({ "wheels" => 5 }, { "$set" => { "x" => 1 } }, upsert: true)
puts "upsert matched=" + r.matched_count.to_s + " upserted_id=" + r.upserted_id.inspect + " upserted_count=" + r.upserted_count.to_s
r = coll.replace_one({ "_id" => 7 }, { "name" => "Mallard", "wheels" => 14 })
puts "replace_one matched=" + r.matched_count.to_s
r = coll.delete_one({ "wheels" => 0 })
puts "delete_one " + r.class.to_s + " deleted_count=" + r.deleted_count.to_s
r = coll.delete_many({ "wheels" => 1 })
puts "delete_many deleted_count=" + r.deleted_count.to_s
show_log(m)

puts "-- write failures"
begin
  coll.insert_one({ "_id" => 7 })
rescue Mongo::Error::OperationFailure => e
  failure("insert_one duplicate", e)
end
begin
  coll.insert_one(nil)
rescue ArgumentError => e
  failure("insert_one nil", e)
end
begin
  coll.insert_many([])
rescue ArgumentError => e
  failure("insert_many empty", e)
end
show_log(m)
[true, false].each do |ordered|
  base = ordered ? 20 : 30
  begin
    coll.insert_many([{ "_id" => base }, { "_id" => 7 }, { "_id" => base + 1 }, { "_id" => 7 }], ordered: ordered)
  rescue Mongo::Error::BulkWriteError => e
    failure("insert_many ordered=" + ordered.to_s, e)
    puts "  result " + e.result.keys.join(",") + " n_inserted=" + e.result["n_inserted"].to_s +
         " inserted_ids=" + e.result["inserted_ids"].inspect
  end
end
show_log(m)

puts "-- sizes and batches"
m = FakeMongod.new(64, 400, 3)
HUB.mongod = m
small = Mongo::Client.new(["small:27017"], database: "t")[:c]
r = small.insert_many([{ "_id" => 1 }, { "_id" => 2 }, { "_id" => 3 }, { "_id" => 4 }, { "_id" => 5 }, { "_id" => 6 }, { "_id" => 7 }])
puts "seven past a batch of three: inserted_count=" + r.inserted_count.to_s
show_log(m)
puts "a document of exactly 64 bytes: n=" + small.insert_one({ "_id" => 200, "s" => "x" * 42 }).n.to_s
begin
  small.insert_one({ "_id" => 201, "s" => "x" * 43 })
rescue Mongo::Error::MaxBSONSize => e
  failure("65 bytes", e)
end
begin
  small.insert_many([{ "_id" => 202 }, { "_id" => 203, "s" => "x" * 60 }])
rescue Mongo::Error::MaxBSONSize => e
  failure("insert_many with one too large", e)
end
show_log(m)
puts "stored " + m.docs.length.to_s
m = FakeMongod.new(64, 300, 100)
HUB.mongod = m
wide = []
i = 0
while i < 6
  wide.push({ "_id" => 100 + i, "s" => "x" * 40 })
  i += 1
end
r = Mongo::Client.new(["small:27017"], database: "t")[:c].insert_many(wide)
puts "six of " + BSON.encode(wide[0]).bytesize.to_s + " bytes in messages of at most 300: inserted_count=" + r.inserted_count.to_s
show_log(m)

puts "-- reads"
m = FakeMongod.new(16 * 1024 * 1024, 48_000_000, 100_000)
HUB.mongod = m
coll = Mongo::Client.new(["db.example:27017"], database: "railyard")[:locomotives]
docs = []
i = 0
while i < 10
  docs.push({ "_id" => i, "wheels" => i % 3 })
  i += 1
end
coll.insert_many(docs)
m.log.clear
view = coll.find({}, sort: { "wheels" => -1 }, projection: { "wheels" => 1 })
puts "view " + view.class.to_s + " sends nothing: " + m.log.length.to_s
puts "find_command " + view.skip(1).limit(3).batch_size(2).find_command.keys.join(",") +
     " | plain " + coll.find.find_command.keys.join(",") + " | single " + coll.find.limit(-2).find_command.keys.join(",")
ids = []
coll.find.batch_size(4).each { |d| ids.push(d["_id"]) }
puts "batch_size 4: " + ids.join(",") + " open cursors " + m.open_cursors.to_s
show_log(m)
puts "skip 2, limit 5, batch_size 2: " + coll.find.skip(2).limit(5).batch_size(2).to_a.map { |d| d["_id"] }.join(",") +
     " open cursors " + m.open_cursors.to_s
show_log(m)
puts "limit 3 with batch_size 2: " +
     coll.find.limit(3).batch_size(2).to_a.length.to_s + " open cursors " + m.open_cursors.to_s
show_log(m)
seen = 0
coll.find.batch_size(3).each do |d|
  seen += 1
  break if seen == 4
end
puts "a block that breaks after 4: open cursors " + m.open_cursors.to_s
show_log(m)
puts "first " + coll.find("wheels" => 2).first["_id"].to_s + " first of none " + coll.find("wheels" => 9).first.inspect
puts "first with batch_size 2 leaves no cursor: " + coll.find.batch_size(2).first["_id"].to_s + " open cursors " + m.open_cursors.to_s
show_log(m)
puts "count_documents " + coll.count_documents.to_s + " wheels=1 " + coll.count_documents("wheels" => 1).to_s +
     " skip 1 limit 2 " + coll.count_documents({ "wheels" => 1 }, skip: 1, limit: 2).to_s +
     " none " + coll.count_documents("wheels" => 9).to_s +
     " view " + coll.find("wheels" => 0).limit(1).count_documents.to_s
puts "estimated_document_count " + coll.estimated_document_count.to_s
puts "distinct " + coll.distinct("wheels").inspect + " filtered " + coll.distinct(:wheels, { "_id" => 4 }).inspect
show_log(m)
puts "drop " + coll.drop.class.to_s
m.drop_missing = true
puts "drop again " + coll.drop.inspect
begin
  coll.database.command(frobnicate: 1)
rescue Mongo::Error::OperationFailure => e
  failure("unknown command", e)
end
show_log(m)

puts "-- broken connection"
m.close_next = true
begin
  coll.database.command(ping: 1)
rescue Mongo::Error::SocketError => e
  failure("closed by the server", e)
end
puts "next command ok=" + coll.database.command(ping: 1).ok?.to_s + " opens=" + m.opens.length.to_s
coll.client.close
puts "after close ok=" + coll.database.command(ping: 1).ok?.to_s + " opens=" + m.opens.length.to_s

puts "-- URIs"
m = FakeMongod.new(16 * 1024 * 1024, 48_000_000, 100_000)
HUB.mongod = m
c = Mongo::Client.new("mongodb://db.example:27018/railyard?appName=depot&connectTimeoutMS=2000&socketTimeoutMS=1500")
puts "database " + c.database.name + " ping ok=" + c.database.command(ping: 1).ok?.to_s + " opened " + m.opens.join("; ")
m.opens.clear
c = Mongo::Client.new("mongodb://db.example/railyard?connectTimeoutMS=2000", database: "depot", connect_timeout: 3)
puts "options over the URI's: database " + c.database.name + " ping ok=" + c.database.command(ping: 1).ok?.to_s +
     " opened " + m.opens.join("; ")
m.opens.clear
c = Mongo::Client.new("mongodb://db.example:")
c.database.command(ping: 1)
puts "an empty port: opened " + m.opens.join("; ")
["mongodb://h/?authMechanism=SCRAM-SHA-256", "mongodb://u@h/?authMechanism=SCRAM-SHA-256",
 "mongodb://u:p@h/?authSource=&authMechanism=SCRAM-SHA-1", "mongodb://@h", "mongodb://u:p@h/?authSource=",
 "mongodb://u:p@h/?authMechanism=PLAIN"].each do |s|
  begin
    Mongo::Client.new(s)
    puts s + ": no error"
  rescue Mongo::Auth::InvalidMechanism => e
    failure(s, e)
  rescue Mongo::Auth::InvalidConfiguration => e
    failure(s, e)
  end
end
[["tls", "mongodb://h/?tls=true", {}], ["ssl option", ["h:27017"], { ssl: true }],
 ["two hosts", "mongodb://a,b/", {}], ["socket", "mongodb://%2Ftmp%2Fmongodb-27017.sock", {}]].each do |t|
  begin
    Mongo::Client.new(t[1], t[2])
    puts t[0] + ": no error"
  rescue ArgumentError => e
    failure(t[0], e)
  end
end
begin
  Mongo::Client.new("mongodb+srv://u:p@cluster0.example.net/railyard")
rescue Mongo::Error::InvalidURI => e
  puts "srv: " + e.class.to_s + " " + e.message.split("\n")[0, 2].join(" | ")
end
begin
  Mongo::Client.new("mongodb://u:p@h:abc")
rescue Mongo::Error::InvalidURI => e
  puts "bad port: " + e.message.split("\n")[0, 2].join(" | ")
end
