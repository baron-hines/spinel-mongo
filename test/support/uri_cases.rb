# Connection strings the URI test shares with its oracle twin, which
# reads them with the mongo gem's Mongo::URI instead, and how both print
# what they read. Each prints the servers, credentials, database and the
# options this driver uses, or the InvalidURI message line by line.

def uri_cases
  [
    "mongodb://localhost",
    "mongodb://localhost:27018/railyard",
    "mongodb://flatbed:s3cret@db.example:27017/railyard?authSource=admin&authMechanism=SCRAM-SHA-256&appName=depot",
    "mongodb://us%40er:p%3Ass%2Fw%25rd@h/db",
    "mongodb://u:p%41ss%25@h",
    "mongodb://u:@h",
    "mongodb://u@h/?authMechanism=scram-sha-1",
    "mongodb://h/?authMechanism=PLAIN",
    "mongodb://h/?authMechanism=FOO",
    "mongodb://h/?connectTimeoutMS=2500&socketTimeoutMS=1500&directConnection=true",
    "mongodb://h/?connectTimeoutMS=abc&socketTimeoutMS=-5&directConnection=yes",
    "mongodb://h/?connectTimeoutMS=12.5&socketTimeoutMS=0",
    "mongodb://h/?CONNECTTIMEOUTMS=100&appname=lower&AuthSource=ext",
    "mongodb://h/?retryWrites=true&w=majority&replicaSet=rs0&readPreference=primary&foo=bar",
    "mongodb://h/?tls=true",
    "mongodb://h/?ssl=false&tls=false",
    "mongodb://h/?tls=true&ssl=false",
    "mongodb://h/?tls=yes",
    "mongodb://[::1]:27019/db",
    "mongodb://[::1]",
    "mongodb://[fe80::1]/",
    "mongodb://a:1,b:2/db",
    "mongodb://a:1,b:2/?directConnection=true",
    "mongodb://h/db?appName=first&appName=second",
    "mongodb://h?appName=noslash",
    "mongodb://h/data%20base",
    "mongodb://h/?&&appName=gaps&",
    "mongodb://h/?app%4Eame=enc%20oded",
    "mongodb://%2Ftmp%2Fmongodb-27017.sock/db",
    "mongodb://h:",
    "mongodb://h,",
    "",
    "http://h",
    "mongodb://",
    "mongodb://h/a/b",
    "mongodb://h/?a=1?b=2",
    "mongodb://u:p@",
    "mongodb://a@b@h",
    "mongodb://h:0",
    "mongodb://h:70000",
    "mongodb://user:secret@h:abc",
    "mongodb://.h",
    "mongodb://h.",
    "mongodb://a..b",
    "mongodb://:27017",
    "mongodb://h:1:2",
    "mongodb://,h",
    "mongodb://h/?appName",
    "mongodb://u:p:q@h",
    "mongodb://h/d:b",
    "mongodb://u/ser:p@h"
  ]
end

def uri_value(v)
  return "nil" if v.nil?
  return "'" + v + "'" if v.is_a?(String)
  return ":" + v.to_s if v.is_a?(Symbol)
  v.to_s
end

def uri_print(servers, user, password, database, options)
  puts "  servers=" + servers.join(",") + " user=" + uri_value(user) + " password=" + uri_value(password) +
       " database=" + database
  line = ""
  [:auth_source, :auth_mech, :app_name, :connect_timeout, :socket_timeout, :direct_connection, :ssl].each do |k|
    line += " " + k.to_s + "=" + uri_value(options[k]) if options.key?(k)
  end
  puts "  options" + line
end

def uri_print_error(e)
  puts "  " + e.class.to_s
  e.message.split("\n").each { |l| puts "  | " + l }
end
