# Twin of test/bson_encode_test.rb through the bson gem.
require "bson"
require_relative "../test/support/bson_fixtures"

bson_fixtures.each do |pair|
  puts pair[0] + " " + pair[1].to_bson.to_s.unpack1("H*")
end
