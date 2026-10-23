# Requests the wire tests share with their oracle twin, which builds them
# with the mongo gem's Mongo::Protocol::Msg instead. Each is a label, a
# request id, the kind 0 body, and the kind 1 identifier and documents
# ("" and [] for none).

def wire_requests
  oid = BSON::ObjectId.from_string("653a1f0e9b1e8a0001a2b3c4")
  many = []
  i = 0
  while i < 1000
    many.push({ "_id" => i, "name" => "car " + i.to_s, "axles" => 4 })
    i += 1
  end
  [
    ["hello", 1, { "hello" => 1, "helloOk" => true, "$db" => "admin" }, "", []],
    ["insert", 42, { "insert" => "locomotives", "ordered" => true, "$db" => "t0" },
     "documents", [{ "name" => "Big Boy" }, { "name" => "Mallard", "wheels" => 14 }]],
    ["update", 43, { "update" => "locomotives", "ordered" => true, "$db" => "t0" },
     "updates", [{ "q" => { "_id" => oid }, "u" => { "$set" => { "wheels" => 16, "rate" => nil } } }]],
    ["delete", 44, { "delete" => "locomotives", "ordered" => true, "$db" => "t0" },
     "deletes", [{ "q" => { "_id" => oid }, "limit" => 1 }]],
    ["find", 45, { "find" => "locomotives", "filter" => {}, "limit" => 1,
                   "sort" => { "_id" => -1 }, "$db" => "t0" }, "", []],
    ["getMore", 46, { "getMore" => BSON::Int64.new(8_123_456_789_012), "collection" => "locomotives",
                      "batchSize" => 100, "$db" => "t0" }, "", []],
    ["max request id", 2147483647, { "ping" => 1, "$db" => "admin" }, "", []],
    ["insert 1000", 47, { "insert" => "cars", "ordered" => true, "$db" => "t0" }, "documents", many]
  ]
end
