# Twin of test/threads_live_test.rb through the mongo gem.
require "mongo"
Mongo::Logger.logger.level = Logger::WARN

port = ARGV.length > 0 ? ARGV[0].to_i : 27217
client = Mongo::Client.new(["127.0.0.1:#{port}"], database: "threads_live")
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

workers = (0...8).map do |n|
  Thread.new do
    1000.times { |j| coll.insert_one({ "thread" => n, "seq" => j }) }
    1000
  end
end
total = workers.sum(&:value)
stop.push(true)
turns = cpu.value

puts "inserted " + total.to_s + ", count " + coll.count_documents.to_s
puts "per thread " + (0...8).map { |t| coll.count_documents("thread" => t) }.join(",")
puts "distinct seq " + coll.distinct("seq").length.to_s + ", distinct thread " + coll.distinct("thread").length.to_s
puts "the CPU-bound thread ran: " + (turns > 0).to_s
client.close
