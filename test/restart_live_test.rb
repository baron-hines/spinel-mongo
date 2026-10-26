# Live: the server restarts between two commands. The client finds its
# connection closed by the server before sending anything on it, opens a
# new one, and the second command succeeds. While the server is down a
# command raises NoServerAvailable, and once it is back the next one
# succeeds. The twin, oracle/restart_live.rb, does the same through the
# gem, which retries the read instead.
require "mongo"
require_relative "support/live_mongod"

PORT = 27325

live_mongod_start("restart", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "restart_live")
coll = client[:depots]
coll.drop
coll.insert_one({ "_id" => 1, "name" => "Cheyenne" })
puts "before: count " + coll.count_documents.to_s

live_mongod_stop("restart")
live_mongod_resume("restart", PORT)
puts "after a restart: count " + coll.count_documents.to_s
coll.insert_one({ "_id" => 2, "name" => "Laramie" })
puts "a write after it: count " + coll.count_documents.to_s

live_mongod_stop("restart")
begin
  coll.count_documents
  puts "server down: no error"
rescue Mongo::Error::NoServerAvailable => e
  puts "server down: " + e.class.to_s
end
live_mongod_resume("restart", PORT)
puts "back up: count " + coll.count_documents.to_s
client.close
live_mongod_stop("restart")
