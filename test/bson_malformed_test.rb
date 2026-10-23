# Each malformed input raises, and the error class matches the gem's
# (checked by oracle/bson_malformed.rb).
require "bson"
require_relative "support/bson_malformed"

bson_malformed_cases.each do |pair|
  begin
    BSON.decode(pair[1])
    puts pair[0] + ": no error"
  rescue BSON::Error => e
    puts pair[0] + ": " + e.class.to_s
  rescue RangeError => e
    puts pair[0] + ": " + e.class.to_s
  rescue EncodingError => e
    puts pair[0] + ": " + e.class.to_s
  end
end
