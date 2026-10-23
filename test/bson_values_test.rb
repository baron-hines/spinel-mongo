# Dual-runtime: the value classes, ObjectId generation, Document's
# Symbol keys, number and string edges through a round trip, encoding
# errors, and the types left out. CRuby's output is the expectation.
require "bson"
require_relative "support/bson_malformed"

def hex(s)
  s.unpack1("H*")
end

def nul
  [0].pack("C")
end

def describe(v)
  if v.is_a?(String)
    "String " + v.encoding.to_s + " " + hex(v)
  elsif v.is_a?(Float)
    "Float " + v.to_s
  elsif v.is_a?(Integer)
    "Integer " + v.to_s
  else
    v.class.to_s
  end
end

def roundtrip(label, value)
  bytes = BSON.encode({ "v" => value })
  back = BSON.decode(bytes)["v"]
  puts label + " " + hex(bytes) + " -> " + describe(back)
end

puts "-- integers"
[0, 1, -1, 2147483647, -2147483648, 2147483648, -2147483649,
 9223372036854775807, -9223372036854775807 - 1].each { |n| roundtrip(n.to_s, n) }
roundtrip("Int64(7)", BSON::Int64.new(7))
puts "Int64 == " + (BSON::Int64.new(7) == BSON::Int64.new(7)).to_s + " " + (BSON::Int64.new(7) == BSON::Int64.new(8)).to_s

puts "-- doubles"
[0.0, -0.0, 0.1, 1.5, -2.25, 1.0e308, 5.0e-324, 2.2250738585072014e-308,
 0.30000000000000004, Float::INFINITY, -Float::INFINITY].each { |f| roundtrip(f.to_s, f) }
puts "NaN " + hex(BSON.encode({ "v" => Float::NAN })) + " " + hex(BSON.encode({ "v" => 0.0 / 0.0 }))
neg_nan = BSON.decode([0x10, 0, 0, 0, 1, 0x76, 0, 0, 0, 0, 0, 0, 0, 0xf8, 0xff, 0].pack("C*"))["v"]
puts "NaN with the sign bit read back nan?=" + neg_nan.nan?.to_s + " written " + hex(BSON.encode({ "v" => neg_nan }))

puts "-- strings"
roundtrip("ascii", "Big Boy")
roundtrip("utf8", "機関車 é")
roundtrip("nul", "a" + nul + "b")
roundtrip("binary-tagged", "x".b)
big = "0123456789" * 7000
back = BSON.decode(BSON.encode({ "v" => big }))["v"]
puts "70 KB string bytes=" + back.bytesize.to_s + " same=" + (back == big).to_s + " enc=" + back.encoding.to_s
puts "utf8 key " + hex(BSON.encode({ "é" => 1 }))
puts "symbol key " + hex(BSON.encode({ a: 1 }))
puts "symbol value " + describe(BSON.decode(BSON.encode({ "a" => :x }))["a"])
begin
  BSON.encode({ "a" + nul + "b" => 1 })
  puts "nul key: no error"
rescue ArgumentError => e
  puts "nul key: " + e.class.to_s
end

puts "-- times"
[Time.at(0, 0).utc, Time.at(1, 999999).utc, Time.at(-1, 1000).utc, Time.at(-893376000, 0).utc].each do |t|
  bytes = BSON.encode({ "v" => t })
  back = BSON.decode(bytes)["v"]
  puts hex(bytes) + " -> " + back.to_i.to_s + "." + back.usec.to_s + " utc=" + back.utc?.to_s
end

puts "-- ObjectId"
a = BSON::ObjectId.from_string("653a1f0e9b1e8a0001a2b3c4")
b = BSON::ObjectId.from_string("653A1F0E9B1E8A0001A2B3C4")
puts a.to_s + " " + a.inspect + " " + a.generation_time.to_i.to_s + " utc=" + a.generation_time.utc?.to_s
puts "== " + (a == b).to_s + " eql? " + a.eql?(b).to_s + " hash " + (a.hash == b.hash).to_s
keyed = {}
keyed[a] = "found"
puts "as a Hash key " + keyed[b].to_s
puts "from_data " + BSON::ObjectId.from_data(a.data).to_s
puts "legal? " + BSON::ObjectId.legal?("653a1f0e9b1e8a0001a2b3c4").to_s + " " +
     BSON::ObjectId.legal?("653a1f0e9b1e8a0001a2b3c").to_s + " " +
     BSON::ObjectId.legal?("653a1f0e9b1e8a0001a2b3cg").to_s
begin
  BSON::ObjectId.from_string("zz")
  puts "from_string zz: no error"
rescue BSON::Error::InvalidObjectId => e
  puts "from_string zz: " + e.class.to_s + " " + e.message
end
now = Time.now.to_i
ids = {}
first = BSON::ObjectId.new
i = 0
while i < 10000
  id = BSON::ObjectId.new
  ids[id.to_s] = true
  i += 1
end
second = BSON::ObjectId.new
puts "10000 distinct " + (ids.size == 10000).to_s
puts "time near now " + ((first.generation_time.to_i - now).abs <= 2).to_s
puts "same process random " + (first.data.byteslice(4, 5) == second.data.byteslice(4, 5)).to_s
c1 = first.data.byteslice(9, 3).unpack("C*")
c2 = second.data.byteslice(9, 3).unpack("C*")
n1 = (c1[0] << 16) | (c1[1] << 8) | c1[2]
n2 = (c2[0] << 16) | (c2[1] << 8) | c2[2]
puts "counter stepped " + ((n2 - n1) % 16777216).to_s
BSON::ObjectId::GENERATOR.counter = 16777215
w1 = BSON::ObjectId.new
w2 = BSON::ObjectId.new
puts "counter wraps " + hex(w1.data.byteslice(9, 3)) + " " + hex(w2.data.byteslice(9, 3))
puts "ordered " + ((first <=> second) < 0).to_s

puts "-- Binary"
u = BSON::Binary.new("ab", :uuid)
puts u.type.to_s + " " + u.subtype.to_s + " " + u.data.encoding.to_s + " == " + (u == BSON::Binary.new("ab", :uuid)).to_s +
     " " + (u == BSON::Binary.new("ab", :generic)).to_s
puts "type_for 0 4 128 200: " + BSON::Binary.type_for(0).to_s + " " + BSON::Binary.type_for(4).to_s + " " +
     BSON::Binary.type_for(128).to_s + " " + BSON::Binary.type_for(200).to_s
begin
  BSON::Binary.new("ab", :nope)
  puts "type :nope: no error"
rescue BSON::Error::InvalidBinaryType => e
  puts "type :nope: " + e.class.to_s
end

puts "-- Document"
d = BSON::Document.new({ name: "Mallard", "wheels" => 14 })
puts d.keys.join(",") + " " + d[:name] + " " + d["wheels"].to_s + " " + d.key?(:name).to_s + " " +
     d.has_key?("wheels").to_s + " " + d.include?(:nope).to_s
d[:built] = 1938
puts d.keys.join(",") + " fetch " + d.fetch(:built).to_s + " " + d.fetch(:nope, "default")
begin
  d.fetch(:nope)
  puts "fetch missing: no error"
rescue KeyError => e
  puts "fetch missing: KeyError"
end
d.delete(:built)
puts d.keys.join(",") + " is a Hash " + d.is_a?(Hash).to_s + " == Hash " + (d == { "name" => "Mallard", "wheels" => 14 }).to_s

puts "-- left out"
bson_left_out_cases.each do |pair|
  begin
    BSON.decode(pair[1])
    puts pair[0] + ": no error"
  rescue BSON::Error::UnsupportedType => e
    puts pair[0] + ": " + e.class.to_s + " " + e.message
  end
end
