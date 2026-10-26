# Live: the server's cursors are closed when iteration stops early. A
# block that breaks out, a block that raises, first on a cursor with more
# batches, and a limit reached while the server's cursor is still open
# each leave no cursor behind, by serverStatus's count of open cursors.
# It has no twin: the gem closes a cursor left this way only when the
# cursor object is garbage collected, so its count stays up here.
require "mongo"
require_relative "support/live_mongod"

PORT = 27322

# serverStatus without its storageEngine and wiredTiger sections, which
# hold BSON timestamps.
def open_cursors(client)
  status = client.use("admin").database.command(serverStatus: 1, storageEngine: 0, wiredTiger: 0).first
  status["metrics"]["cursor"]["open"]["total"]
end

live_mongod_start("kill_cursors", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "kill_cursors_live")
coll = client[:readings]
docs = []
i = 0
while i < 50
  docs.push({ "_id" => i })
  i += 1
end
coll.insert_many(docs)
puts "open at the start " + open_cursors(client).to_s

seen = 0
coll.find.batch_size(10).each do |d|
  seen += 1
  break if seen == 15
end
puts "break after 15 of 50 in batches of 10: open " + open_cursors(client).to_s

begin
  coll.find.batch_size(10).each { |d| raise ArgumentError, "stop" if d["_id"] == 3 }
rescue ArgumentError => e
  puts "a block that raised " + e.message + ": open " + open_cursors(client).to_s
end

puts "first with batch_size 10: _id " + coll.find.batch_size(10).first["_id"].to_s + ", open " + open_cursors(client).to_s
puts "limit 15 in batches of 10: " + coll.find.limit(15).batch_size(10).to_a.length.to_s + ", open " + open_cursors(client).to_s
puts "all 50: " + coll.find.batch_size(10).to_a.length.to_s + ", open " + open_cursors(client).to_s
client.close
live_mongod_stop("kill_cursors")
