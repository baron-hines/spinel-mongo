# A server cursor: the first batch from a find, aggregate or
# listCollections reply, then getMore until the server's cursor id is 0.
# A limit stops it early. When iteration stops with the server's cursor
# still open (the limit was reached, the block broke out, or it raised),
# the cursor is closed with killCursors so it doesn't wait out the
# server's ten-minute timeout.
require "bson"
require "mongo/errors"

module Mongo
  class Cursor
    # batch_size and limit are 0 for none.
    def initialize(connection, db, reply, batch_size, limit)
      @connection = connection
      @db = db
      @batch_size = batch_size
      @limit = limit
      @returned = 0
      @id = 0
      @batch = []
      @collection = ""
      cur = reply["cursor"]
      if cur.is_a?(Hash)
        id = cur["id"]
        @id = id if id.is_a?(Integer)
        first = cur["firstBatch"]
        @batch = first if first.is_a?(Array)
        ns = cur["ns"]
        # getMore and killCursors name the collection: the namespace
        # after the database's name and its dot.
        if ns.is_a?(String) && ns.length > db.length + 1
          @collection = ns[db.length + 1, ns.length - db.length - 1]
        end
      end
    end

    # The server's cursor id, 0 once it is exhausted or closed.
    def id
      @id
    end

    def each
      begin
        while true
          i = 0
          while i < @batch.length && !done?
            doc = @batch[i]
            i += 1
            if doc.is_a?(Hash)
              @returned += 1
              yield doc
            end
          end
          break if @id == 0 || done?
          get_more
        end
      ensure
        kill if @id != 0
      end
      nil
    end

    def done?
      @limit > 0 && @returned >= @limit
    end

    def get_more
      cmd = BSON::Document.new
      cmd["getMore"] = BSON::Int64.new(@id)
      cmd["collection"] = @collection
      size = @batch_size
      if @limit > 0
        left = @limit - @returned
        size = left if size == 0 || left < size
      end
      cmd["batchSize"] = size if size > 0
      cmd["$db"] = @db
      reply = @connection.command(cmd)
      @id = 0
      @batch = []
      cur = reply["cursor"]
      if cur.is_a?(Hash)
        id = cur["id"]
        @id = id if id.is_a?(Integer)
        nxt = cur["nextBatch"]
        @batch = nxt if nxt.is_a?(Array)
      end
      nil
    end

    # killCursors, on the connection the cursor lives on. Nothing is
    # raised from here: a broken connection has lost the cursor anyway.
    def kill
      id = @id
      @id = 0
      return nil if @connection.closed?
      cmd = BSON::Document.new
      cmd["killCursors"] = @collection
      cmd["cursors"] = [BSON::Int64.new(id)]
      cmd["$db"] = @db
      begin
        @connection.command(cmd)
      rescue Mongo::Error
        nil
      end
      nil
    end
  end
end
