# A pretend mongod for the dual-runtime client tests: one collection's
# documents in memory, enough of find, getMore, killCursors, insert,
# update, delete, aggregate, count, distinct, drop and listCollections to
# drive the collection API, and a log of every command it is sent. Its
# limits are small, so batching shows with a few documents. Filters match
# by equality on top-level fields only.
require "mongo/connection"

class FakeMongod
  def initialize(max_bson, max_message, max_batch)
    @max_bson = max_bson
    @max_message = max_message
    @max_batch = max_batch
    @docs = []
    @log = []
    @cursors = {}
    @cursor_names = {}
    @next_cursor = 1000
    @opens = []
    @drop_missing = false
    @close_next = false
  end

  def docs
    @docs
  end

  def log
    @log
  end

  def opens
    @opens
  end

  def open_cursors
    @cursors.length
  end

  # drop of an empty collection fails with code 26, as servers before
  # 7.0 answered.
  def drop_missing=(v)
    @drop_missing = v
  end

  # The next request is answered by closing the connection.
  def close_next=(v)
    @close_next = v
  end

  def close_next?
    @close_next
  end

  def opened(line)
    @opens.push(line)
    nil
  end

  def matches?(doc, filter)
    filter.each do |k, v|
      return false unless doc[k.to_s] == v
    end
    true
  end

  def matching(filter)
    out = []
    @docs.each { |d| out.push(d) if matches?(d, filter) }
    out
  end

  def fail(code, code_name, text)
    { "ok" => 0.0, "errmsg" => text, "code" => code, "codeName" => code_name }
  end

  # A cursor reply: the first n of docs now, the rest left on a cursor.
  def cursor_reply(ns, docs, n, key)
    first = n > 0 && n < docs.length ? docs[0, n] : docs
    rest = docs[first.length, docs.length - first.length]
    id = 0
    if rest.length > 0
      id = @next_cursor
      @next_cursor += 1
      @cursors[id] = rest
      @cursor_names[id] = ns
    end
    { "cursor" => { key => first, "id" => BSON::Int64.new(id), "ns" => ns }, "ok" => 1.0 }
  end

  def handle(cmd, seq_id, seq_docs)
    name = cmd.keys[0]
    @log.push(name + " " + cmd.keys.join(",") + (seq_id == "" ? "" : " " + seq_id + ":" + seq_docs.length.to_s))
    if name == "hello"
      return { "isWritablePrimary" => true, "maxBsonObjectSize" => @max_bson, "maxMessageSizeBytes" => @max_message,
               "maxWriteBatchSize" => @max_batch, "maxWireVersion" => 25, "ok" => 1.0 }
    end
    ns = cmd["$db"].to_s + "." + cmd[name].to_s
    if name == "insert"
      n = 0
      errors = []
      i = 0
      while i < seq_docs.length
        d = seq_docs[i]
        dup = false
        @docs.each { |x| dup = true if x["_id"] == d["_id"] }
        if dup
          errors.push({ "index" => i, "code" => 11000, "errmsg" => "E11000 duplicate key error collection: " + ns +
                                                                   " index: _id_ dup key: { _id: " + d["_id"].to_s + " }" })
          break if cmd["ordered"] == true
        else
          @docs.push(d)
          n += 1
        end
        i += 1
      end
      reply = { "n" => n, "ok" => 1.0 }
      reply["writeErrors"] = errors if errors.length > 0
      return reply
    end
    if name == "find"
      found = matching(cmd["filter"])
      skip = cmd["skip"]
      found = found[skip, found.length - skip] || [] if skip.is_a?(Integer)
      limit = cmd["limit"]
      found = found[0, limit] if limit.is_a?(Integer) && limit < found.length
      size = cmd["batchSize"]
      return cursor_reply(ns, found, size.is_a?(Integer) ? size : 0, "firstBatch")
    end
    if name == "getMore"
      id = cmd["getMore"].to_i
      return fail(43, "CursorNotFound", "cursor id " + id.to_s + " not found") unless @cursors.key?(id)
      if cmd["collection"].to_s != @cursor_names[id].split(".", 2)[1]
        return fail(13, "Unauthorized", "Requested getMore on namespace '" + cmd["collection"].to_s + "'")
      end
      rest = @cursors[id]
      size = cmd["batchSize"]
      n = size.is_a?(Integer) && size < rest.length ? size : rest.length
      batch = rest[0, n]
      left = rest[n, rest.length - n]
      if left.length > 0
        @cursors[id] = left
      else
        @cursors.delete(id)
        @cursor_names.delete(id)
        id = 0
      end
      return { "cursor" => { "nextBatch" => batch, "id" => BSON::Int64.new(id), "ns" => ns }, "ok" => 1.0 }
    end
    if name == "killCursors"
      killed = []
      cmd["cursors"].each do |c|
        @cursors.delete(c.to_i)
        @cursor_names.delete(c.to_i)
        killed.push(c)
      end
      return { "cursorsKilled" => killed, "ok" => 1.0 }
    end
    if name == "update"
      st = seq_docs[0]
      found = matching(st["q"])
      found = found[0, 1] unless st["multi"] == true
      if found.length == 0 && st["upsert"] == true
        @docs.push({ "_id" => 99 })
        return { "n" => 1, "upserted" => [{ "index" => 0, "_id" => 99 }], "nModified" => 0, "ok" => 1.0 }
      end
      return { "n" => found.length, "nModified" => found.length, "ok" => 1.0 }
    end
    if name == "delete"
      st = seq_docs[0]
      found = matching(st["q"])
      found = found[0, 1] if st["limit"] == 1
      kept = []
      @docs.each { |d| kept.push(d) unless found.include?(d) }
      @docs = kept
      return { "n" => found.length, "ok" => 1.0 }
    end
    if name == "aggregate"
      found = []
      cmd["pipeline"].each do |stage|
        found = matching(stage["$match"]) if stage.key?("$match")
        found = found[stage["$skip"], found.length] || [] if stage.key?("$skip")
        found = found[0, stage["$limit"]] if stage.key?("$limit")
      end
      batch = found.length == 0 ? [] : [{ "_id" => 1, "n" => found.length }]
      return { "cursor" => { "firstBatch" => batch, "id" => BSON::Int64.new(0), "ns" => ns }, "ok" => 1.0 }
    end
    return { "n" => @docs.length, "ok" => 1.0 } if name == "count"
    if name == "distinct"
      values = []
      matching(cmd["query"]).each do |d|
        v = d[cmd["key"]]
        values.push(v) unless v.nil? || values.include?(v)
      end
      return { "values" => values, "ok" => 1.0 }
    end
    if name == "drop"
      return fail(26, "NamespaceNotFound", "ns not found") if @drop_missing && @docs.length == 0
      @docs = []
      return { "ok" => 1.0 }
    end
    if name == "listCollections"
      names = [{ "name" => "locomotives" }, { "name" => "system.views" }, { "name" => "tenders" }]
      return cursor_reply(cmd["$db"].to_s + ".$cmd.listCollections", names, 1, "firstBatch")
    end
    return { "ok" => 1.0 } if name == "ping"
    fail(59, "CommandNotFound", "no such command: '" + name + "'")
  end
end

# One connection to the FakeMongod, over Connection's transport duck.
class FakeTransport
  def initialize(mongod)
    @mongod = mongod
    @queue = []
  end

  def write(bytes)
    if @mongod.close_next?
      @mongod.close_next = false
      @queue.push("".b)
      return nil
    end
    p = Mongo::Wire::Parser.new
    p.feed(bytes)
    p.try_next
    seq = []
    p.seq_docs.each { |raw| seq.push(BSON.decode(raw)) }
    reply = @mongod.handle(p.document, p.seq_id, seq)
    op = Mongo::Wire.op_msg(1, reply)
    @queue.push(op.byteslice(0, 8) + [p.request_id].pack("l<") + op.byteslice(12, op.bytesize - 12))
    nil
  end

  def read_some(max)
    return "".b if @queue.length == 0
    @queue.shift
  end

  def close
    nil
  end
end

class FakeConnector
  def initialize(mongod)
    @mongod = mongod
  end

  def open(host, port, connect_timeout, socket_timeout)
    @mongod.opened(host + ":" + port.to_s + " connect=" + connect_timeout.to_s + " socket=" + socket_timeout.to_s)
    FakeTransport.new(@mongod)
  end
end
