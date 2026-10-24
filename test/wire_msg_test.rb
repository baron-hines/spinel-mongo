# The bytes of OP_MSG requests: a command alone, and with its documents
# in a kind 1 section. The snapshot is checked against the mongo gem by
# oracle/wire_msg.rb. The largest prints its length and its two ends.
require "mongo"
require_relative "support/wire_requests"

wire_requests.each do |r|
  bytes = Mongo::Wire.op_msg(r[1], r[2], r[3], r[4])
  hex = bytes.unpack1("H*")
  if bytes.bytesize > 512
    hex = bytes.bytesize.to_s + " bytes " + hex[0, 120] + " .. " + hex[hex.length - 80, 80]
  end
  puts r[0] + " " + hex
end
