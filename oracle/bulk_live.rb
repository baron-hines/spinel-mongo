# Twin of test/bulk_live_test.rb through the mongo gem. The gem splits
# 120,000 documents into two halves where this driver sends 100,000 and
# 20,000; both are two insert commands. The gem's MaxBSONSize message
# ends with where it happened, " (on 127.0.0.1:27217)", which is cut.
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

def strip_note(message)
  message.sub(/ \(on [^)]*\)\z/, "")
end

def inserts(client)
  status = client.use("admin").database.command(serverStatus: 1, storageEngine: 0, wiredTiger: 0).first
  status["metrics"]["commands"]["insert"]["total"]
end

port = ARGV.length > 0 ? ARGV[0].to_i : 27217
client = Mongo::Client.new(["127.0.0.1:#{port}"], database: "bulk_live", direct_connection: true)
coll = client[:readings]
coll.drop
docs = (0...120_000).map { |i| { "i" => i } }
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
    indexes = res["writeErrors"].map { |we| we["index"].to_s + ":" + we["code"].to_s }
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
  puts "one byte over: " + e.class.to_s + " " + strip_note(e.message) + ", stored " + coll.count_documents.to_s
end
coll.drop
client.close
