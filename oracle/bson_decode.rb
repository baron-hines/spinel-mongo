# Twin of test/bson_decode_test.rb through the bson gem.
require "bson"
require_relative "../test/support/bson_fixtures"

bson_fixtures.each do |pair|
  bytes = pair[1].to_bson.to_s
  buf = BSON::ByteBuffer.new(bytes)
  doc = BSON::Document.from_bson(buf)
  puts pair[0] + " consumed=" + (buf.read_position == bytes.bytesize).to_s
  bson_dump(doc, "  ")
  puts "  roundtrip " + (doc.to_bson.to_s == bytes).to_s
end

reply = BSON::Document.from_bson(BSON::ByteBuffer.new(bson_fixture("reply_cursor").to_bson.to_s))
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
