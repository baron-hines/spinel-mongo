# Connect, write, read, change and remove documents, and handle a
# server error. The same file runs compiled by Spinel against this
# driver and under CRuby against the mongo gem:
#
#   spinel $(spin flags) -I . examples/quickstart.rb -o build/quickstart
#   MONGODB_URI=mongodb://127.0.0.1:27017/examples build/quickstart
#   MONGODB_URI=mongodb://127.0.0.1:27017/examples ruby examples/quickstart.rb
#
# examples/run.sh does both against a throwaway mongod and diffs them.
require "mongo"

client = Mongo::Client.new(ENV.fetch("MONGODB_URI", "mongodb://127.0.0.1:27017/examples"))
locos = client[:locomotives]
locos.drop

# insert_one hands back the _id it made; insert_many takes an Array.
big_boy = locos.insert_one({ "name" => "Big Boy", "wheels" => 24, "built" => 1941 }).inserted_id
locos.insert_many([
  { "name" => "Mallard", "wheels" => 14, "built" => 1938 },
  { "name" => "Flying Scotsman", "wheels" => 12, "built" => 1923 },
  { "name" => "Rocket", "wheels" => 4, "built" => 1829 }
])
puts "inserted " + locos.count_documents({}).to_s + " locomotives"

# A query is a view: sort, skip, limit and projection chain, and the
# documents come back in batches as each walks the cursor.
locos.find({ "wheels" => { "$gt" => 10 } }).sort({ "built" => 1 }).projection({ "_id" => 0, "name" => 1, "built" => 1 }).each do |doc|
  puts "  " + doc["name"] + " (" + doc["built"].to_s + ")"
end

doc = locos.find({ "_id" => big_boy }).first
puts "Big Boy's _id is an ObjectId: " + doc["_id"].is_a?(BSON::ObjectId).to_s

r = locos.update_one({ "_id" => big_boy }, { "$set" => { "retired" => true } })
puts "update_one matched " + r.matched_count.to_s + ", modified " + r.modified_count.to_s
r = locos.update_many({ "built" => { "$lt" => 1940 } }, { "$set" => { "retired" => true } })
puts "update_many modified " + r.modified_count.to_s
puts "retired: " + locos.count_documents({ "retired" => true }).to_s

names = locos.distinct("name", { "wheels" => { "$lt" => 20 } })
puts "under 20 wheels: " + names.sort.join(", ")

r = locos.delete_many({ "built" => { "$lt" => 1900 } })
puts "delete_many removed " + r.deleted_count.to_s
puts "left: " + locos.estimated_document_count.to_s

# A failed command raises the gem's error, with the server's code.
begin
  locos.insert_one({ "_id" => big_boy, "name" => "Big Boy again" })
rescue Mongo::Error::OperationFailure => e
  puts "duplicate _id: code " + e.code.to_s
end

locos.drop
client.close
