# Several threads writing through one client. The client keeps one
# connection, and each thread takes its turn on it for a whole round
# trip, so threads need no locking of their own. Run it as
# examples/quickstart.rb says.
require "mongo"

client = Mongo::Client.new(ENV.fetch("MONGODB_URI", "mongodb://127.0.0.1:27017/examples"))
counts = client[:counts]
counts.drop

threads = []
[0, 1, 2, 3].each do |worker|
  threads << Thread.new do
    i = 0
    while i < 250
      counts.insert_one({ "worker" => worker, "i" => i })
      i += 1
    end
  end
end
threads.each(&:join)

puts "documents: " + counts.count_documents({}).to_s
[0, 1, 2, 3].each do |worker|
  puts "worker " + worker.to_s + ": " + counts.count_documents({ "worker" => worker }).to_s
end

counts.drop
client.close
