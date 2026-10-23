# Documents the BSON tests share with their oracle twins, which build
# them with the bson gem instead. Only names both define are used:
# BSON::ObjectId.from_string, BSON::Int64.new, BSON::Binary.new and
# BSON::Document.new.

def bson_nul
  [0].pack("C")
end

def bson_fixtures
  oid = BSON::ObjectId.from_string("653a1f0e9b1e8a0001a2b3c4")
  built = Time.at(-893376000, 0).utc          # 1941-09-05, before the epoch
  inspected = Time.at(1761177600, 123456).utc # sub-millisecond part truncated
  [
    ["hello", {
      "hello" => 1, "helloOk" => true,
      "client" => {
        "driver" => { "name" => "spinel-mongo", "version" => "0.0.0" },
        "os" => { "type" => "Linux", "name" => "linux", "architecture" => "x86_64" },
        "platform" => "Spinel"
      },
      "saslSupportedMechs" => "admin.app",
      "$db" => "admin"
    }],
    ["insert", {
      "insert" => "locomotives", "ordered" => true,
      "documents" => [
        { "_id" => oid, "name" => "Big Boy", "wheels" => 24, "built" => built,
          "tractive_lbf" => 135375.5, "retired" => true, "notes" => nil,
          "inspected_at" => inspected }
      ],
      "$db" => "test"
    }],
    ["find", {
      "find" => "locomotives",
      "filter" => { "wheels" => { "$gt" => 4 }, "name" => { "$in" => ["Big Boy", "Mallard"] } },
      "sort" => { "built" => -1 }, "limit" => 2, "batchSize" => 1, "$db" => "test"
    }],
    ["symbol_keys", { find: "locomotives", filter: { name: "Mallard" }, "$db": "test" }],
    ["symbol_value", { "status" => :retired, "tags" => [:steam, :freight] }],
    ["getmore", { "getMore" => BSON::Int64.new(123), "collection" => "locomotives", "$db" => "test" }],
    ["numbers", {
      "i32_min" => -2147483648, "i32_max" => 2147483647,
      "i64_low" => -2147483649, "i64_high" => 2147483648,
      "i64_min" => -9223372036854775807 - 1, "i64_max" => 9223372036854775807,
      "forced_i64" => BSON::Int64.new(1), "forced_i64_neg" => BSON::Int64.new(-1), "zero" => 0,
      "d_tenth" => 0.1, "d_neg_zero" => -0.0, "d_big" => 1.0e308, "d_tiny" => 5.0e-324,
      "d_inf" => Float::INFINITY, "d_ninf" => -Float::INFINITY, "d_17" => 0.30000000000000004,
      "d_nan" => Float::NAN, "d_nan_div" => 0.0 / 0.0
    }],
    ["strings", {
      "empty" => "", "nul_inside" => "a" + bson_nul + "b", "utf8" => "機関車 é",
      "nested_empty" => {}, "array_empty" => [],
      "mixed_array" => [1, "two", 3.0, nil, true, { "k" => [] }]
    }],
    ["binaries", {
      "generic" => BSON::Binary.new("x" + bson_nul + bson_nul + "y", :generic),
      "uuid" => BSON::Binary.new([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x47, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0x00].pack("C*"), :uuid),
      "old" => BSON::Binary.new("ab", :old),
      "md5" => BSON::Binary.new("0123456789abcdef", :md5),
      "user" => BSON::Binary.new("u", :user),
      "empty" => BSON::Binary.new("", :generic)
    }],
    ["times", {
      "epoch" => Time.at(0, 0).utc,
      "ms" => Time.at(1, 999000).utc,
      "before_epoch_ms" => Time.at(-1, 1000).utc,
      "y2038" => Time.at(2147483648, 0).utc
    }],
    ["document_input", BSON::Document.new({ "a" => 1, b: BSON::Document.new({ c: "d" }) })],
    ["reply_cursor", {
      "cursor" => {
        "firstBatch" => [{ "_id" => oid, "name" => "Big Boy", "wheels" => 24 }],
        "id" => BSON::Int64.new(7310152818270717953), "ns" => "test.locomotives"
      },
      "ok" => 1.0
    }],
    ["reply_write_error", {
      "n" => 0,
      "writeErrors" => [{ "index" => 0, "code" => 11000, "errmsg" => "E11000 duplicate key error" }],
      "ok" => 1.0
    }],
    ["reply_command_error", { "ok" => 0.0, "errmsg" => "command not found", "code" => 59, "codeName" => "CommandNotFound" }]
  ]
end

# One line per value with its class, recursively, so a decode by
# spinel-mongo and a decode by the gem can be diffed as text.
def bson_dump(v, indent)
  if v.is_a?(BSON::Document)
    puts indent + "Document(" + v.size.to_s + ")"
    v.each do |k, x|
      puts indent + "  " + k.to_s + ":"
      bson_dump(x, indent + "    ")
    end
  elsif v.is_a?(Hash)
    puts indent + "Hash(" + v.size.to_s + ")"
  elsif v.is_a?(Array)
    puts indent + "Array(" + v.length.to_s + ")"
    v.each { |x| bson_dump(x, indent + "  ") }
  elsif v.is_a?(String)
    puts indent + "String " + v.encoding.to_s + " " + v.bytesize.to_s + " " + v.unpack1("H*")
  elsif v.is_a?(Float)
    puts indent + "Float " + v.to_s + " " + [v].pack("E").unpack1("H*")
  elsif v.is_a?(Integer)
    puts indent + "Integer " + v.to_s
  elsif v.is_a?(BSON::ObjectId)
    puts indent + "ObjectId " + v.to_s
  elsif v.is_a?(BSON::Binary)
    puts indent + "Binary " + v.type.to_s + " " + v.data.unpack1("H*") + " " + v.data.encoding.to_s
  elsif v.is_a?(Time)
    puts indent + "Time " + (v.to_i * 1000 + v.usec / 1000).to_s + " utc=" + v.utc?.to_s
  elsif v.nil?
    puts indent + "nil"
  elsif v == true || v == false
    puts indent + "Boolean " + v.to_s
  else
    puts indent + "?" + v.class.to_s
  end
end

def bson_fixture(name)
  bson_fixtures.each { |pair| return pair[1] if pair[0] == name }
  raise ArgumentError, "no fixture " + name
end
