# Dual-runtime: Mongo::Wire::Parser over a scripted byte stream. T0's
# seven replies with awkward chunk boundaries (a byte at a time, two in
# one read, the header split, 200 KB in 7 KB pieces, a kind 1 section
# sharing a read with the next reply, the checksum flag), many replies in
# one read, then each kind of malformed reply. CRuby's output is the
# expectation.
require "mongo/wire"

def le32(n)
  [n].pack("l<")
end

# Raw sections: kind 0 holds one document; kind 1 an identifier and
# documents.
def kind0(doc)
  [0].pack("C") + BSON.encode(doc)
end

def kind1(id, docs)
  payload = id.b + [0].pack("C")
  docs.each { |d| payload << BSON.encode(d) }
  [1].pack("C") + le32(payload.bytesize + 4) + payload
end

# A reply: the header, flags, the sections, and with the checksum flag a
# stand-in CRC.
def frame(request_id, response_to, op, flags, sections)
  extra = (flags & 1) != 0 ? [0x12345678].pack("V") : "".b
  le32(16 + 4 + sections.bytesize + extra.bytesize) + le32(request_id) + le32(response_to) +
    le32(op) + [flags].pack("V") + sections + extra
end

def reply(request_id, response_to, flags, doc)
  frame(request_id, response_to, 2013, flags, kind0(doc))
end

def describe(p)
  doc = p.document
  line = "frame id=" + p.request_id.to_s + " to=" + p.response_to.to_s + " op=" + p.op_code.to_s +
         " flags=" + p.flags.to_s + " len=" + p.length.to_s
  if doc.key?("echo")
    line = line + " echo=" + doc["echo"].bytesize.to_s
  elsif doc.key?("blob")
    line = line + " blob=" + doc["blob"].data.bytesize.to_s
  else
    line = line + " keys=" + doc.keys.join(",")
  end
  if p.seq_docs.length > 0
    line = line + " seq=" + p.seq_id + ":" + p.seq_docs.length.to_s
    p.seq_docs.each { |d| line = line + " " + BSON.decode(d).keys.join(",") }
  end
  line
end

def drain(p)
  while p.try_next
    puts describe(p)
  end
end

puts "-- the seven replies"
req = Mongo::Wire.op_msg(42, { "insert" => "locomotives", "ordered" => true, "$db" => "t0" },
                         "documents", [{ "name" => "Big Boy" }, { "name" => "Mallard", "wheels" => 14 }])
blob = BSON::Binary.new([0, 255].pack("C*") * 100_000)
replies = [
  reply(101, 42, 0, { "echo" => req.unpack1("H*"), "ok" => 1.0 }),
  reply(102, 42, 0, { "n" => 2, "ok" => 1.0 }),
  reply(103, 42, 0, { "n" => 3, "ok" => 1.0 }),
  reply(104, 42, 0, { "split" => "header", "ok" => 1.0 }),
  reply(105, 42, 0, { "blob" => blob, "ok" => 1.0 }),
  frame(106, 42, 2013, 0, kind0({ "ok" => 1.0 }) + kind1("documents", [{ "a" => 1 }, { "b" => "two" }])),
  reply(107, 42, 1, { "checksummed" => true, "ok" => 1.0 })
]
p = Mongo::Wire::Parser.new
feeds = 0
r = replies[0]
i = 0
while i < r.bytesize
  p.feed(r.byteslice(i, 1))
  feeds += 1
  drain(p)
  i += 1
end
p.feed(replies[1] + replies[2])
drain(p)
p.feed(replies[3].byteslice(0, 3))
puts "header split: " + p.try_next.to_s + " buffered " + p.buffered.to_s
p.feed(replies[3].byteslice(3, replies[3].bytesize - 3))
drain(p)
r = replies[4]
i = 0
while i < r.bytesize
  p.feed(r.byteslice(i, 7000))
  drain(p)
  i += 7000
end
p.feed(replies[5] + replies[6].byteslice(0, 10))
drain(p)
p.feed(replies[6].byteslice(10, replies[6].bytesize - 10))
drain(p)
puts "frames " + p.frames.to_s + " leftover " + p.buffered.to_s + " byte feeds " + feeds.to_s

puts "-- many replies in one read"
p = Mongo::Wire::Parser.new
stream = "".b
i = 0
while i < 500
  stream << reply(1000 + i, i, 0, { "n" => i, "ok" => 1.0 })
  i += 1
end
p.feed(stream + reply(1500, 500, 0, { "n" => 500, "ok" => 1.0 }).byteslice(0, 30))
sum = 0
last = 0
while p.try_next
  sum += p.document["n"]
  last = p.response_to
end
puts "frames " + p.frames.to_s + " sum " + sum.to_s + " last to=" + last.to_s + " buffered " + p.buffered.to_s
p.feed(reply(1500, 500, 0, { "n" => 500, "ok" => 1.0 }).byteslice(30, 1000))
puts "rest: " + p.try_next.to_s + " n=" + p.document["n"].to_s + " buffered " + p.buffered.to_s

puts "-- optional flag"
p = Mongo::Wire::Parser.new
p.feed(reply(9, 8, 1 << 16, { "ok" => 1.0 }))
puts "exhaustAllowed: " + p.try_next.to_s + " flags=" + p.flags.to_s

puts "-- malformed"
ok = kind0({ "ok" => 1.0 })
doc = BSON.encode({ "ok" => 1.0 })
bad = [
  ["negative length", le32(-1) + le32(1) + le32(0) + le32(2013)],
  ["zero length", le32(0) + le32(1) + le32(0) + le32(2013)],
  ["header only", le32(16) + le32(1) + le32(0) + le32(2013)],
  ["no section", le32(20) + le32(1) + le32(0) + le32(2013) + le32(0)],
  ["moreToCome", frame(1, 0, 2013, 2, ok)],
  ["unknown required flag", frame(1, 0, 2013, 4, ok)],
  ["OP_REPLY", frame(1, 0, 1, 0, ok)],
  ["unknown section kind", frame(1, 0, 2013, 0, [2].pack("C") + doc)],
  ["section past the end", frame(1, 0, 2013, 0, [0].pack("C") + le32(200) + doc.byteslice(4, doc.bytesize - 4))],
  ["section size under 5", frame(1, 0, 2013, 0, [0].pack("C") + le32(4) + doc.byteslice(4, doc.bytesize - 4))],
  ["kind byte at the end", frame(1, 0, 2013, 0, ok + [0].pack("C"))],
  ["two kind 0", frame(1, 0, 2013, 0, ok + ok)],
  ["kind 1 only", frame(1, 0, 2013, 0, kind1("documents", [{ "a" => 1 }]))],
  ["kind 1 identifier unterminated", frame(1, 0, 2013, 0, ok + [1].pack("C") + le32(13) + "documents".b)],
  ["kind 1 document past its section", frame(1, 0, 2013, 0, ok + [1].pack("C") + le32(4 + 10 + 4) +
                                                              "documents".b + [0].pack("C") + le32(50))]
]
bad.each do |pair|
  p = Mongo::Wire::Parser.new
  p.feed(pair[1])
  begin
    puts pair[0] + ": " + p.try_next.to_s
  rescue Mongo::Error => e
    puts pair[0] + ": " + e.class.to_s + " " + e.message
  end
end

# Refused from the first four bytes, before the rest arrives.
p = Mongo::Wire::Parser.new(1024)
p.feed(le32(2000))
begin
  puts "over the limit: " + p.try_next.to_s
rescue Mongo::Error::MaxMessageSize => e
  puts "over the limit: " + e.class.to_s + " " + e.message
end
p = Mongo::Wire::Parser.new
p.feed(le32(Mongo::Wire::MAX_MESSAGE_SIZE + 1))
begin
  puts "over 48 MiB: " + p.try_next.to_s
rescue Mongo::Error::MaxMessageSize => e
  puts "over 48 MiB: " + e.class.to_s + " " + e.message
end
