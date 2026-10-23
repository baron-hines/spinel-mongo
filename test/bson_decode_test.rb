# Decodes each fixture's bytes, dumps every value with its class, and
# checks that encoding the result gives the same bytes back where it
# should. Then reads a cursor reply the way the driver will, narrowing
# with is_a?. The snapshot is checked against the bson gem by
# oracle/bson_decode.rb.
require "bson"
require_relative "support/bson_fixtures"

bson_fixtures.each do |pair|
  bytes = BSON.encode(pair[1])
  r = BSON::Reader.new(bytes)
  doc = r.document
  puts pair[0] + " consumed=" + (r.pos == bytes.bytesize).to_s
  bson_dump(doc, "  ")
  puts "  roundtrip " + (BSON.encode(doc) == bytes).to_s
end

reply = BSON.decode(BSON.encode(bson_fixture("reply_cursor")))
cursor = reply[:cursor]
if cursor.is_a?(Hash)
  id = cursor["id"]
  batch = cursor[:firstBatch]
  puts "cursor id " + id.to_s + " int=" + id.is_a?(Integer).to_s
  if batch.is_a?(Array)
    first = batch[0]
    if first.is_a?(Hash)
      name = first[:name]
      wheels = first["wheels"]
      puts "first " + name.to_s + " wheels+1=" + (wheels.is_a?(Integer) ? (wheels + 1).to_s : "?")
    end
  end
end
puts "ok " + (reply["ok"] == 1.0).to_s
puts "key? " + reply.key?(:ok).to_s + " " + reply.key?("cursor").to_s + " " + reply.key?(:nope).to_s
puts "fetch " + reply.fetch(:ok).to_s + " " + reply.fetch(:nope, "default").to_s
puts "dig " + reply.dig(:cursor, :ns).to_s
