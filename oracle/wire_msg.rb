# Twin of test/wire_msg_test.rb through the mongo gem's OP_MSG.
require "mongo"
require_relative "../test/support/wire_requests"

wire_requests.each do |r|
  seqs = r[4].empty? ? [] : [Mongo::Protocol::Msg::Section1.new(r[3], r[4])]
  msg = Mongo::Protocol::Msg.new([], {}, r[2], *seqs)
  msg.instance_variable_set(:@request_id, r[1])
  bytes = msg.serialize.to_s
  hex = bytes.unpack1("H*")
  if bytes.bytesize > 512
    hex = bytes.bytesize.to_s + " bytes " + hex[0, 120] + " .. " + hex[hex.length - 80, 80]
  end
  puts r[0] + " " + hex
end
