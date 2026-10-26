# Connection strings read by Mongo::URI: hosts, percent-decoded
# credentials and database, the options the driver uses (case-insensitive
# names, values the gem drops dropped, repeats keeping the first), and
# the gem's InvalidURI messages. The snapshot is checked against the
# mongo gem's Mongo::URI by oracle/uri.rb.
require "mongo/uri"
require_relative "support/uri_cases"

uri_cases.each do |s|
  puts s
  begin
    u = Mongo::URI.get(s)
    uri_print(u.servers, u.user, u.password, u.database, u.uri_options)
  rescue Mongo::Error::InvalidURI => e
    uri_print_error(e)
  end
end
