# Encodes the shared fixtures and prints each as hex. The snapshot is
# checked against the bson gem by oracle/bson_encode.rb.
require "bson"
require_relative "support/bson_fixtures"

bson_fixtures.each do |pair|
  puts pair[0] + " " + BSON.encode(pair[1]).unpack1("H*")
end
