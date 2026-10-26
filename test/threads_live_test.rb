# Live, compiled with threads: eight green threads insert 1,000
# documents each through one client and its one connection, beside a
# CPU-bound thread that never waits. Every insert lands once, and the
# CPU-bound thread finishes its work too. The twin, oracle/threads_live.rb,
# runs the same through the gem and its connection pool.
require "mongo"
require_relative "support/live_mongod"

PORT = 27323

live_mongod_start("threads", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "threads_live")
coll = client[:inserts]
coll.drop

stop = Queue.new
cpu = Thread.new do
  turns = 0
  x = 0
  while stop.empty?
    i = 0
    while i < 1000
      x = (x * 31 + i) % 1_000_003
      i += 1
    end
    turns += 1
  end
  turns
end

# Each thread's number comes from the each block, not Thread.new's
# argument; see the README's Spinel notes.
workers = []
[0, 1, 2, 3, 4, 5, 6, 7].each do |n|
  workers.push(Thread.new do
    j = 0
    while j < 1000
      coll.insert_one({ "thread" => n, "seq" => j })
      j += 1
    end
    j
  end)
end
total = 0
workers.each { |w| total += w.value }
stop.push(true)
turns = cpu.value

puts "inserted " + total.to_s + ", count " + coll.count_documents.to_s
per = []
t = 0
while t < 8
  per.push(coll.count_documents("thread" => t))
  t += 1
end
puts "per thread " + per.join(",")
puts "distinct seq " + coll.distinct("seq").length.to_s + ", distinct thread " + coll.distinct("thread").length.to_s
puts "the CPU-bound thread ran: " + (turns > 0).to_s
client.close
live_mongod_stop("threads")
