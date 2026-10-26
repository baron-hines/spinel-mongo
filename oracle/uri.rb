# Twin of test/uri_test.rb through the mongo gem's Mongo::URI. The gem's
# warnings for options it drops go to its logger, which is silenced.
require "mongo"
require_relative "../test/support/uri_cases"

Mongo::Logger.logger.level = Logger::FATAL

uri_cases.each do |s|
  puts s
  begin
    u = Mongo::URI.get(s)
    c = u.credentials
    uri_print(u.servers, c[:user], c[:password], u.database, u.uri_options)
  rescue Mongo::Error::InvalidURI => e
    uri_print_error(e)
  end
end
