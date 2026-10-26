# Live: a prefork server's pattern. The parent connects, then forks two
# workers that write through the client they inherited. Each worker
# sees it is in a new process and opens its own connection, so the
# parent's socket is never shared, and the parent's connection still
# works after them. whatsmyuri shows the three client addresses. The
# twin, oracle/fork_live.rb, does the same through the gem.
require "mongo"
require_relative "support/live_mongod"

module ForkOS
  ffi_func :sp_net_fork,     [],     :int
  ffi_func :sp_net_exit,     [:int], :int
  ffi_func :sp_net_wait_any, [],     :int
end

PORT = 27324

def client_address(client)
  client.use("admin").database.command(whatsmyuri: 1).first["you"]
end

live_mongod_start("fork", PORT)
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "fork_live")
coll = client[:writes]
coll.drop
parent = client_address(client)
coll.insert_one({ "_id" => "parent", "you" => parent })

[0, 1].each do |w|
  if ForkOS.sp_net_fork == 0
    j = 0
    while j < 100
      coll.insert_one({ "worker" => w, "seq" => j })
      j += 1
    end
    coll.insert_one({ "_id" => "worker " + w.to_s, "you" => client_address(client) })
    ForkOS.sp_net_exit(0)
  end
end
ForkOS.sp_net_wait_any
ForkOS.sp_net_wait_any

puts "worker 0 wrote " + coll.count_documents("worker" => 0).to_s + ", worker 1 wrote " +
     coll.count_documents("worker" => 1).to_s
addresses = []
coll.find("you" => { "$exists" => true }).each do |d|
  you = d["you"].to_s
  addresses.push(you) unless addresses.include?(you)
end
puts "client addresses seen: " + addresses.length.to_s
puts "the parent's connection after the workers: count " + coll.count_documents.to_s +
     ", same address " + (client_address(client) == parent).to_s
client.close
live_mongod_stop("fork")
