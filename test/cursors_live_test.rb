# Live: reads through the collection API against a real mongod. A find
# of 250 documents in batches of 100 (the getMores counted by the
# server's serverStatus), sort with skip and limit, a limit past the
# first batch, first, projection, count_documents with and without skip
# and limit, estimated_document_count, distinct, the update and delete
# results, collection_names and drop. Spinel-only, like the other live
# tests; oracle/cursors_live.rb runs the same flow through the mongo gem.
require "mongo"
require_relative "support/live_mongod"

PORT = 27320

# serverStatus without its storageEngine and wiredTiger sections, which
# hold BSON timestamps.
def get_mores(client)
  status = client.use("admin").database.command(serverStatus: 1, storageEngine: 0, wiredTiger: 0).first
  status["metrics"]["commands"]["getMore"]["total"]
end

live_mongod_start("cursors", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "cursors_live")
coll = client[:readings]
coll.drop
docs = []
i = 0
while i < 250
  docs.push({ "_id" => i, "n" => i, "group" => i % 5 })
  i += 1
end
puts "inserted " + coll.insert_many(docs).inserted_count.to_s

before = get_mores(client)
seen = 0
sum = 0
coll.find.sort("n" => 1).batch_size(100).each do |d|
  seen += 1
  sum += d["n"]
end
puts "batch_size 100: " + seen.to_s + " documents, sum " + sum.to_s + ", getMores " + (get_mores(client) - before).to_s

page = coll.find.sort("n" => -1).skip(10).limit(25).to_a
puts "sort -1, skip 10, limit 25: " + page.length.to_s + " from " + page[0]["n"].to_s + " to " + page[page.length - 1]["n"].to_s

before = get_mores(client)
puts "limit 150, batch_size 100: " + coll.find.limit(150).batch_size(100).to_a.length.to_s +
     ", getMores " + (get_mores(client) - before).to_s

puts "first of group 3: n=" + coll.find("group" => 3).sort("n" => 1).first["n"].to_s +
     ", of group 9: " + coll.find("group" => 9).first.inspect
d = coll.find({ "n" => 7 }, projection: { "_id" => 0, "group" => 1 }).first
puts "projection: " + d.keys.join(",") + " group=" + d["group"].to_s

puts "count_documents all " + coll.count_documents.to_s + ", group 1 " + coll.count_documents("group" => 1).to_s +
     ", skip 10 limit 20 " + coll.count_documents({}, skip: 10, limit: 20).to_s +
     ", group 1 skip 45 " + coll.count_documents({ "group" => 1 }, skip: 45).to_s +
     ", none " + coll.count_documents("group" => 9).to_s
puts "estimated_document_count " + coll.estimated_document_count.to_s
puts "distinct group " + coll.distinct("group").sort.inspect + ", where n < 3 " + coll.distinct("n", { "n" => { "$lt" => 3 } }).sort.inspect

r = coll.update_many({ "group" => 0 }, { "$set" => { "even" => true } })
puts "update_many matched " + r.matched_count.to_s + " modified " + r.modified_count.to_s
r = coll.update_many({ "group" => 0 }, { "$set" => { "even" => true } })
puts "again matched " + r.matched_count.to_s + " modified " + r.modified_count.to_s
r = coll.update_one({ "_id" => 1000 }, { "$set" => { "n" => 1000 } }, upsert: true)
puts "upsert matched " + r.matched_count.to_s + " upserted_id " + r.upserted_id.inspect + " upserted_count " + r.upserted_count.to_s
r = coll.replace_one({ "_id" => 1000 }, { "n" => 1001 })
puts "replace_one matched " + r.matched_count.to_s + " modified " + r.modified_count.to_s + " now " +
     coll.find("_id" => 1000).first.keys.join(",")
puts "delete_one " + coll.delete_one("group" => 4).deleted_count.to_s + ", delete_many " +
     coll.delete_many("group" => 4).deleted_count.to_s + ", left " + coll.count_documents.to_s

client[:other].insert_one({ "x" => 1 })
puts "collection_names " + client.database.collection_names.sort.join(",")
puts "drop " + coll.drop.ok?.to_s + ", names " + client.database.collection_names.sort.join(",")
client[:other].drop
client.close
live_mongod_stop("cursors")
