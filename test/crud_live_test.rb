# Live: the collection API against a real mongod, the flow
# oracle/crud_live.rb runs through the mongo gem. hello through
# Database#command, insert_many, a find with batch_size 1 that needs
# getMores, count_documents, update_one, delete_one, a duplicate key, an
# unknown command, and a read back. Server-chosen values (ObjectIds,
# cursor ids) print as properties. Spinel-only, like the other live
# tests.
require "mongo"
require_relative "support/live_mongod"

PORT = 27319

live_mongod_start("crud", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "crud_live", direct_connection: true)
h = client.database.command(hello: 1).first
puts "hello ok=" + h["ok"].to_s + " writable=" + h["isWritablePrimary"].to_s +
     " wire>=21=" + (h["maxWireVersion"] >= 21).to_s

coll = client[:locomotives]
coll.drop
docs = [
  { "_id" => BSON::ObjectId.new, "name" => "Big Boy", "wheels" => 24, "retired" => true },
  { "_id" => BSON::ObjectId.new, "name" => "Mallard", "wheels" => 14, "retired" => true },
  { "_id" => BSON::ObjectId.new, "name" => "Flying Scotsman", "wheels" => 12, "retired" => false }
]
r = coll.insert_many(docs)
puts "insert_many inserted_count=" + r.inserted_count.to_s +
     " same ids=" + (r.inserted_ids == docs.map { |d| d["_id"] }).to_s

coll.find({ "wheels" => { "$gt" => 12 } }).sort("wheels" => -1).batch_size(1).each do |d|
  puts "find " + d["name"] + " wheels=" + d["wheels"].to_s + " _id is ObjectId=" + d["_id"].is_a?(BSON::ObjectId).to_s
end

puts "count_documents retired=" + coll.count_documents("retired" => true).to_s
r = coll.update_one({ "name" => "Mallard" }, { "$set" => { "wheels" => 16 } })
puts "update_one matched_count=" + r.matched_count.to_s + " modified_count=" + r.modified_count.to_s
r = coll.delete_one("retired" => false)
puts "delete_one deleted_count=" + r.deleted_count.to_s

begin
  coll.insert_one(docs[0])
  puts "duplicate not raised"
rescue Mongo::Error::OperationFailure => e
  puts "duplicate OperationFailure code=" + e.code.to_s
end
begin
  client.database.command(frobnicate: 1)
  puts "unknown not raised"
rescue Mongo::Error::OperationFailure => e
  puts "unknown OperationFailure code=" + e.code.to_s + " code_name=" + e.code_name.to_s
end

d = coll.find("name" => "Mallard").first
puts "read back " + d.keys.join(",") + " wheels=" + d["wheels"].to_s +
     " same _id=" + (d["_id"] == docs[1]["_id"]).to_s
coll.drop
client.close
live_mongod_stop("crud")
