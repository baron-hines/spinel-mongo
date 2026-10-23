# Twin of test/bson_malformed_test.rb through the bson gem.
require "bson"
require_relative "../test/support/bson_malformed"

bson_malformed_cases.each do |pair|
  begin
    BSON::Document.from_bson(BSON::ByteBuffer.new(pair[1]))
    puts pair[0] + ": no error"
  rescue BSON::Error => e
    puts pair[0] + ": " + e.class.to_s
  rescue RangeError => e
    puts pair[0] + ": " + e.class.to_s
  rescue EncodingError => e
    puts pair[0] + ": " + e.class.to_s
  end
end
