# Twin of test/auth_live_test.rb through the mongo gem. The harness's
# mongod runs without --auth, so this starts its own on the next port,
# with a throwaway --dbpath under build/oracle/, and stops it at the end.
# Two notes on the gem's messages are cut before printing, since this
# driver's messages don't carry them (see the README's ledger): the
# server an Unauthorized came from (", used server: ...") and where an
# OperationFailure happened (" (on ...)").
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

def strip_note(message)
  message.sub(/ \(on [^)]*\)\z/, "")
end

def strip_server(message)
  message.sub(/, used server: [^ ]+ \([A-Za-z]+\)\)/, ")")
end

port = (ARGV.length > 0 ? ARGV[0].to_i : 27217) + 1
dir = "build/oracle/auth_live"
system("rm -rf #{dir} && mkdir -p #{dir}/db")
system("mongod --port #{port} --bind_ip 127.0.0.1 --dbpath #{dir}/db --fork --logpath #{dir}/mongod.log " \
       "--wiredTigerCacheSizeGB 0.25 --auth > /dev/null 2>&1") or abort("oracle: mongod --auth did not start")
at_exit { system("mongod --shutdown --dbpath #{dir}/db > /dev/null 2>&1") }

HOST = ["127.0.0.1:#{port}"]

def client(**opts)
  Mongo::Client.new(HOST, { database: "auth_live", direct_connection: true, auth_source: "admin",
                            server_selection_timeout: 5 }.merge(opts))
end

def whoami(c)
  users = c.use("admin").database.command(connectionStatus: 1).first["authInfo"]["authenticatedUsers"]
  users.map { |u| u["user"] + "@" + u["db"] }.join(",")
end

# The gem doesn't say which mechanism it negotiated, so the server's
# record of the login is asked instead, as the test's "used" is checked
# against it there.
def used_mechanism(c, user)
  info = c.use("admin").database.command(usersInfo: user, showCredentials: false).first
  mechs = info["users"][0]["mechanisms"]
  mechs.include?("SCRAM-SHA-256") ? "SCRAM-SHA-256" : "SCRAM-SHA-1"
end

MECHS = { "" => nil, "SCRAM-SHA-256" => :scram256, "SCRAM-SHA-1" => :scram }

def login(label, user, password, mechanism)
  opts = { user: user, password: password }
  opts[:auth_mech] = MECHS[mechanism] if MECHS[mechanism]
  c = client(**opts)
  who = whoami(c)
  used = mechanism == "" ? used_mechanism(c, user) : mechanism
  puts label + ": " + used + " as " + who
  c
end

def refused(label, user, password, auth_source, mechanism)
  opts = { user: user, password: password, auth_source: auth_source }
  opts[:auth_mech] = MECHS[mechanism] if MECHS[mechanism]
  c = client(**opts)
  begin
    c.database.command(ping: 1)
    puts label + ": no error"
  rescue Mongo::Auth::Unauthorized => e
    puts label + ": " + e.class.to_s + " " + strip_server(e.message) + " code=" + e.code.inspect
  ensure
    c.close
  end
end

c = client
c.use("admin").database.command(createUser: "app", pwd: "s3cret pass", roles: [{ role: "root", db: "admin" }])
c.close
c = login("app, negotiated", "app", "s3cret pass", "")
c.use("admin").database.command(createUser: "legacy", pwd: "older pass", mechanisms: ["SCRAM-SHA-1"],
                                roles: [{ role: "readWrite", db: "auth_live" }])
c[:locomotives].drop
c.close
login("app, SCRAM-SHA-256", "app", "s3cret pass", "SCRAM-SHA-256").close
login("app, SCRAM-SHA-1", "app", "s3cret pass", "SCRAM-SHA-1").close
c = login("legacy, negotiated", "legacy", "older pass", "")
r = c[:locomotives].insert_one({ "_id" => 1, "name" => "Big Boy" })
puts "legacy insert n=" + r.n.to_s
begin
  c.use("elsewhere")[:locomotives].find.to_a
  puts "legacy outside its role: no error"
rescue Mongo::Error::OperationFailure => e
  # The server's message goes on to echo the command, which the gem
  # sends with more fields.
  puts "legacy outside its role: " + e.class.to_s + " " + e.message[0, e.message.index(" to execute")] + " code=" + e.code.to_s
end
c.close

refused("wrong password", "app", "wrong pass", "admin", "")
refused("wrong password, SCRAM-SHA-1", "app", "wrong pass", "admin", "SCRAM-SHA-1")
refused("wrong authSource", "app", "s3cret pass", "auth_live", "")
refused("legacy asked for SCRAM-SHA-256", "legacy", "older pass", "admin", "SCRAM-SHA-256")

c = Mongo::Client.new(HOST, database: "auth_live", direct_connection: true)
begin
  c[:locomotives].find.to_a
  puts "no login: no error"
rescue Mongo::Error::OperationFailure => e
  puts "no login: " + e.class.to_s + " " + strip_note(e.message) + " code=" + e.code.to_s
end
c.close
