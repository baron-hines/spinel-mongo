# Live: insert_many against a real mongod. 120,000 small documents,
# which take two insert commands (counted by serverStatus) since the
# server takes at most 100,000 a batch; ordered and unordered inserts
# with duplicate keys, raising BulkWriteError with the gem's message and
# result; and the 16 MiB limit, where a document of exactly 16 MiB goes
# in and one a byte larger is refused before it is sent. Spinel-only,
# like the other live tests; oracle/bulk_live.rb runs the same flow
# through the mongo gem.
require "mongo"
require_relative "support/live_mongod"

PORT = 27321

# serverStatus without its storageEngine and wiredTiger sections, which
# hold BSON timestamps.
def inserts(client)
  status = client.use("admin").database.command(serverStatus: 1, storageEngine: 0, wiredTiger: 0).first
  status["metrics"]["commands"]["insert"]["total"]
end

live_mongod_start("bulk", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "bulk_live")
coll = client[:readings]
coll.drop
docs = []
i = 0
while i < 120_000
  docs.push({ "i" => i })
  i += 1
end
before = inserts(client)
r = coll.insert_many(docs)
puts "120000: inserted_count " + r.inserted_count.to_s + ", ids " + r.inserted_ids.length.to_s +
     ", all ObjectIds " + r.inserted_ids.all? { |id| id.is_a?(BSON::ObjectId) }.to_s +
     ", insert commands " + (inserts(client) - before).to_s + ", counted " + coll.count_documents.to_s
coll.drop

[true, false].each do |ordered|
  coll.drop
  coll.insert_one({ "_id" => 2 })
  begin
    coll.insert_many([{ "_id" => 1 }, { "_id" => 2 }, { "_id" => 3 }, { "_id" => 2 }], ordered: ordered)
    puts "ordered " + ordered.to_s + ": no error"
  rescue Mongo::Error::BulkWriteError => e
    puts "ordered " + ordered.to_s + ": " + e.class.to_s + " " + e.message
    res = e.result
    indexes = []
    res["writeErrors"].each { |we| indexes.push(we["index"].to_s + ":" + we["code"].to_s) }
    puts "  result " + res.keys.join(",") + " n_inserted=" + res["n_inserted"].to_s + " n=" + res["n"].to_s +
         " inserted_ids=" + res["inserted_ids"].inspect + " errors=" + indexes.join(",") +
         " stored=" + coll.count_documents.to_s
  end
end

coll.drop
r = coll.insert_one({ "_id" => 1, "s" => "x" * 16_777_194 })
puts "exactly 16 MiB: n=" + r.n.to_s + ", stored " + coll.find.projection("s" => 0).to_a.length.to_s
begin
  coll.insert_one({ "_id" => 2, "s" => "x" * 16_777_195 })
  puts "one byte over: no error"
rescue Mongo::Error::MaxBSONSize => e
  puts "one byte over: " + e.class.to_s + " " + e.message + ", stored " + coll.count_documents.to_s
end
coll.drop
client.close
live_mongod_stop("bulk")
