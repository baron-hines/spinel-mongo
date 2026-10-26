# Twin of test/restart_live_test.rb through the mongo gem. It restarts
# its mongod, so it starts its own, two ports after the shared one.
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

port = (ARGV.length > 0 ? ARGV[0].to_i : 27217) + 2
dir = "build/oracle/restart_live"
START = "mongod --port #{port} --bind_ip 127.0.0.1 --dbpath #{dir}/db --fork --logpath #{dir}/mongod.log " \
        "--logappend --wiredTigerCacheSizeGB 0.25 > /dev/null 2>&1"
STOP = "mongod --shutdown --dbpath #{dir}/db > /dev/null 2>&1"
system("rm -rf #{dir} && mkdir -p #{dir}/db")
system(START) or abort("oracle: mongod did not start")
at_exit { system(STOP) }

client = Mongo::Client.new(["127.0.0.1:#{port}"], database: "restart_live", server_selection_timeout: 2)
coll = client[:depots]
coll.drop
coll.insert_one({ "_id" => 1, "name" => "Cheyenne" })
puts "before: count " + coll.count_documents.to_s

system(STOP)
system(START)
puts "after a restart: count " + coll.count_documents.to_s
coll.insert_one({ "_id" => 2, "name" => "Laramie" })
puts "a write after it: count " + coll.count_documents.to_s

system(STOP)
begin
  coll.count_documents
  puts "server down: no error"
rescue Mongo::Error::NoServerAvailable => e
  puts "server down: " + e.class.to_s
end
system(START)
puts "back up: count " + coll.count_documents.to_s
client.close
