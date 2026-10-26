# Live: SCRAM against a real mongod started with --auth. Its first user
# is made through the localhost exception, then a user with both
# mechanisms and one with SCRAM-SHA-1 only. Logins with each mechanism,
# chosen and negotiated, what the server says each user is, and each
# refusal: a wrong password, the wrong authSource, SCRAM-SHA-256 for a
# user without it, a command before any login, and a user outside its
# role. Then logins through Mongo::Client's options. Spinel-only (the
# committed .expected keeps spin test from running it under CRuby);
# oracle/auth_live.rb runs the same flow through the mongo gem.
require "mongo"
require_relative "support/live_mongod"

PORT = 27318

# The handshake asks which mechanisms user has in auth_source.
def open_connection(user, auth_source)
  t = Mongo::Transport.new("127.0.0.1", PORT, 5.0, nil)
  c = Mongo::Connection.new(t, t.address)
  c.handshake("", user == "" ? "" : auth_source + "." + user)
  c
end

def whoami(c)
  users = c.command({ "connectionStatus" => 1, "$db" => "admin" })["authInfo"]["authenticatedUsers"]
  names = []
  users.each { |u| names.push(u["user"] + "@" + u["db"]) }
  names.join(",")
end

def login(label, user, password, mechanism)
  c = open_connection(user, "admin")
  used = c.authenticate(user, password, "auth_live", "admin", mechanism)
  puts label + ": " + used + " as " + whoami(c)
  c
end

def refused(label, user, password, auth_source, mechanism)
  c = open_connection(user, auth_source)
  begin
    c.authenticate(user, password, "auth_live", auth_source, mechanism)
    puts label + ": no error"
  rescue Mongo::Auth::Unauthorized => e
    puts label + ": " + e.class.to_s + " " + e.message + " code=" + e.code.inspect
  end
end

live_mongod_start("auth", PORT, "--auth")

c = open_connection("", "")
c.command({ "createUser" => "app", "pwd" => "s3cret pass", "roles" => [{ "role" => "root", "db" => "admin" }], "$db" => "admin" })
c.close
c = login("app, negotiated", "app", "s3cret pass", "")
c.command({ "createUser" => "legacy", "pwd" => "older pass", "mechanisms" => ["SCRAM-SHA-1"],
            "roles" => [{ "role" => "readWrite", "db" => "auth_live" }], "$db" => "admin" })
c.command({ "drop" => "locomotives", "$db" => "auth_live" }) rescue nil
c.close
login("app, SCRAM-SHA-256", "app", "s3cret pass", Mongo::Scram::SHA256).close
login("app, SCRAM-SHA-1", "app", "s3cret pass", Mongo::Scram::SHA1).close
c = login("legacy, negotiated", "legacy", "older pass", "")
r = c.command_seq({ "insert" => "locomotives", "$db" => "auth_live" }, "documents", [{ "_id" => 1, "name" => "Big Boy" }])
puts "legacy insert n=" + r["n"].to_s
begin
  c.command({ "find" => "locomotives", "$db" => "elsewhere" })
  puts "legacy outside its role: no error"
rescue Mongo::Error::OperationFailure => e
  # The server's message goes on to echo the command, which the gem
  # sends with more fields.
  puts "legacy outside its role: " + e.class.to_s + " " + e.message[0, e.message.index(" to execute")] + " code=" + e.code.to_s
end
c.close

refused("wrong password", "app", "wrong pass", "admin", "")
refused("wrong password, SCRAM-SHA-1", "app", "wrong pass", "admin", Mongo::Scram::SHA1)
refused("wrong authSource", "app", "s3cret pass", "auth_live", "")
refused("legacy asked for SCRAM-SHA-256", "legacy", "older pass", "admin", Mongo::Scram::SHA256)

c = open_connection("", "")
begin
  c.command({ "find" => "locomotives", "$db" => "auth_live" })
  puts "no login: no error"
rescue Mongo::Error::OperationFailure => e
  puts "no login: " + e.class.to_s + " " + e.message + " code=" + e.code.to_s
end
c.close

client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "auth_live", user: "legacy", password: "older pass",
                                auth_source: "admin")
puts "client as legacy: " + client[:locomotives].find("_id" => 1).first["name"] + ", count " +
     client[:locomotives].count_documents.to_s
client.close
client = Mongo::Client.new(["127.0.0.1:" + PORT.to_s], database: "auth_live", user: "app", password: "wrong pass",
                                auth_source: "admin", auth_mech: :scram256)
begin
  client[:locomotives].count_documents
  puts "client with a wrong password: no error"
rescue Mongo::Auth::Unauthorized => e
  puts "client with a wrong password: " + e.class.to_s + " " + e.message
end
client.close
client = Mongo::Client.new("mongodb://app:s3cret%20pass@" + "127.0.0.1:" + PORT.to_s + "/auth_live?authSource=admin&appName=auth_live")
puts "client from a URI: " + client.database.name + ", count " + client[:locomotives].count_documents.to_s
client.close

live_mongod_stop("auth")
