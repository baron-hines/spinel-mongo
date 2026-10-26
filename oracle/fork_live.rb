# Twin of test/fork_live_test.rb through the mongo gem, which also opens
# new connections in a forked child.
require "mongo"
Mongo::Logger.logger.level = Logger::WARN

port = ARGV.length > 0 ? ARGV[0].to_i : 27217

def client_address(client)
  client.use("admin").database.command(whatsmyuri: 1).first["you"]
end

client = Mongo::Client.new(["127.0.0.1:#{port}"], database: "fork_live", max_pool_size: 1)
coll = client[:writes]
coll.drop
parent = client_address(client)
coll.insert_one({ "_id" => "parent", "you" => parent })

[0, 1].each do |w|
  Process.fork do
    100.times { |j| coll.insert_one({ "worker" => w, "seq" => j }) }
    coll.insert_one({ "_id" => "worker #{w}", "you" => client_address(client) })
    exit!(0)
  end
end
Process.wait
Process.wait

puts "worker 0 wrote " + coll.count_documents("worker" => 0).to_s + ", worker 1 wrote " +
     coll.count_documents("worker" => 1).to_s
addresses = coll.find("you" => { "$exists" => true }).map { |d| d["you"] }.uniq
puts "client addresses seen: " + addresses.length.to_s
puts "the parent's connection after the workers: count " + coll.count_documents.to_s +
     ", same address " + (client_address(client) == parent).to_s
client.close
