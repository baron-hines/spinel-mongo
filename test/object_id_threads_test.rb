# Dual-runtime: ObjectIds drawn by eight threads at once are all
# distinct. Spinel's threads run in parallel, so the generator's counter
# needs its Mutex there; under CRuby the test passes either way.
require "bson"

seen = {}
lock = Mutex.new
dups = 0
threads = []
[0, 1, 2, 3, 4, 5, 6, 7].each do |n|
  threads.push(Thread.new do
    ids = []
    i = 0
    while i < 20_000
      ids.push(BSON::ObjectId.new.to_s)
      i += 1
    end
    lock.lock
    begin
      ids.each do |id|
        dups += 1 if seen.key?(id)
        seen[id] = true
      end
    ensure
      lock.unlock
    end
    n
  end)
end
threads.each { |t| t.join }
puts "ids " + seen.length.to_s + ", repeats " + dups.to_s
