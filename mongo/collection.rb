# Mongo::Collection: the gem's CRUD methods, each one command (insert_many
# a command a batch), with the gem's results and errors.
require "bson"
require "mongo/errors"
require "mongo/wire"
require "mongo/results"
require "mongo/cursor"
require "mongo/view"

module Mongo
  class Collection
    TOO_LARGE = "The document exceeds maximum allowed BSON object size after serialization"

    def initialize(database, name)
      @database = database
      @name = name
    end

    def name
      @name
    end

    def database
      @database
    end

    def client
      @database.client
    end

    def namespace
      @database.name + "." + @name
    end

    def connection
      @database.client.server.connection
    end

    # A View over the documents matching filter; nothing is sent until it
    # is iterated. options: sort, projection, limit, skip, batch_size.
    def find(filter = nil, options = {})
      Mongo::Collection::View.new(self, filter.nil? ? BSON::Document.new : filter, options)
    end

    # Inserts one document, with a new ObjectId as _id when it has none.
    # The caller's Hash is left as it is, as the gem leaves it. A write
    # error raises OperationFailure, and a document over the server's
    # maxBsonObjectSize raises MaxBSONSize before anything is sent.
    def insert_one(document, opts = {})
      raise ArgumentError, "Document to be inserted cannot be nil" if document.nil?
      conn = connection
      id = Collection.id_or_new(document)
      enc = BSON::Encoder.new
      if Collection.id_of(document).nil?
        enc.document_with_id(document, id)
      else
        enc.document(document)
      end
      bytes = enc.bytes
      raise Mongo::Error::MaxBSONSize, TOO_LARGE if bytes.bytesize > conn.max_bson_object_size
      reply = conn.round_trip_encoded(write_command("insert", true), "documents", [bytes])
      raise Mongo::Error::OperationFailure.from_reply(reply) if Mongo::Error::OperationFailure.failure?(reply)
      Mongo::Operation::Insert::Result.new(reply, [id])
    end

    # Inserts documents in as few insert commands as the server's
    # maxWriteBatchSize and maxMessageSizeBytes allow. ordered (default
    # true) stops at the first write error. Write errors raise
    # BulkWriteError with the gem's result Hash. Every document is
    # measured before any is sent, so one over maxBsonObjectSize raises
    # MaxBSONSize with nothing inserted.
    def insert_many(documents, options = {})
      raise ArgumentError, "Bulk write requests cannot be empty" if documents.length == 0
      ordered = options[:ordered] != false
      conn = connection
      encoded = []
      ids = []
      documents.each do |doc|
        # Pushing the id this way keeps the Array's elements mixed on
        # Spinel; see id_or_new.
        ids.push(Collection.id_or_new(doc))
        enc = BSON::Encoder.new
        if Collection.id_of(doc).nil?
          enc.document_with_id(doc, ids[ids.length - 1])
        else
          enc.document(doc)
        end
        bytes = enc.bytes
        raise Mongo::Error::MaxBSONSize, TOO_LARGE if bytes.bytesize > conn.max_bson_object_size
        encoded.push(bytes)
      end
      body = write_command("insert", ordered)
      overhead = Mongo::Wire.overhead(BSON.encode(body).bytesize, "documents")
      n = 0
      inserted = []
      errors = []
      concern_errors = []
      start = 0
      while start < encoded.length
        size = overhead
        stop = start
        while stop < encoded.length && stop - start < conn.max_write_batch_size &&
              (stop == start || size + encoded[stop].bytesize <= conn.max_message_size)
          size += encoded[stop].bytesize
          stop += 1
        end
        reply = conn.round_trip_encoded(body, "documents", encoded[start, stop - start])
        raise Mongo::Error::OperationFailure.from_reply(reply) if reply["ok"] != 1
        got = reply["n"]
        n += got if got.is_a?(Integer)
        bad = {}
        wes = reply["writeErrors"]
        if wes.is_a?(Array)
          wes.each do |we|
            if we.is_a?(Hash)
              index = we["index"]
              index = 0 unless index.is_a?(Integer)
              bad[index] = true
              we["index"] = start + index
              errors.push(we)
            end
          end
        end
        i = start
        while i < stop
          inserted.push(ids[i]) unless bad.key?(i - start)
          i += 1
        end
        wce = reply["writeConcernError"]
        concern_errors.push(wce) if wce.is_a?(Hash)
        start = stop
        break if ordered && errors.length > 0
      end
      results = BSON::Document.new
      results["n_inserted"] = n
      results["n"] = n
      results["inserted_ids"] = inserted
      results["writeErrors"] = errors if errors.length > 0
      results["writeConcernErrors"] = concern_errors if concern_errors.length > 0
      if errors.length > 0 || concern_errors.length > 0
        raise Mongo::Error::BulkWriteError.new(results)
      end
      Mongo::BulkWrite::Result.new(results)
    end

    # options: upsert.
    def update_one(filter, update, options = {})
      update_command(filter, update, false, options[:upsert] == true)
    end

    def update_many(filter, update, options = {})
      update_command(filter, update, true, options[:upsert] == true)
    end

    def replace_one(filter, replacement, options = {})
      update_command(filter, replacement, false, options[:upsert] == true)
    end

    def delete_one(filter = nil, options = {})
      delete_command(filter, 1)
    end

    def delete_many(filter = nil, options = {})
      delete_command(filter, 0)
    end

    # The number of documents matching filter, by the aggregate pipeline
    # the gem sends. options: skip, limit.
    def count_documents(filter = {}, options = {})
      pipeline = [{ "$match" => filter }]
      skip = options[:skip]
      pipeline.push({ "$skip" => skip }) if skip.is_a?(Integer)
      limit = options[:limit]
      pipeline.push({ "$limit" => limit }) if limit.is_a?(Integer)
      pipeline.push({ "$group" => { "_id" => 1, "n" => { "$sum" => 1 } } })
      cmd = BSON::Document.new
      cmd["aggregate"] = @name
      cmd["pipeline"] = pipeline
      cmd["cursor"] = BSON::Document.new
      cmd["$db"] = @database.name
      conn = connection
      count = 0
      Mongo::Cursor.new(conn, @database.name, conn.command(cmd), 0, 0).each do |doc|
        v = doc["n"]
        count = v if v.is_a?(Integer)
      end
      count
    end

    # The server's count from the collection's metadata, by the count
    # command.
    def estimated_document_count(options = {})
      cmd = BSON::Document.new
      cmd["count"] = @name
      cmd["$db"] = @database.name
      v = connection.command(cmd)["n"]
      v.is_a?(Integer) ? v : 0
    end

    # The distinct values of field_name among the documents matching
    # filter.
    def distinct(field_name, filter = nil, options = {})
      cmd = BSON::Document.new
      cmd["distinct"] = @name
      cmd["key"] = field_name.to_s
      cmd["query"] = filter.nil? ? BSON::Document.new : filter
      cmd["$db"] = @database.name
      values = connection.command(cmd)["values"]
      values.is_a?(Array) ? values : []
    end

    # Drops the collection. A server older than 7.0 answers a collection
    # that doesn't exist with code 26, and that returns false, as in the
    # gem; newer servers say ok.
    def drop(opts = {})
      cmd = BSON::Document.new
      cmd["drop"] = @name
      cmd["$db"] = @database.name
      Mongo::Operation::Result.new(connection.command(cmd))
    rescue Mongo::Error::OperationFailure => e
      raise e unless e.code == 26
      false
    end

    # The document's _id, or nil when it has none, as the gem finds it.
    def self.id_of(doc)
      id = doc["_id"]
      id = doc[:_id] if id.nil?
      id
    end

    # The document's _id, or a new ObjectId. On Spinel, an Array that
    # one branch pushes an ObjectId onto and another a mixed value takes
    # ObjectId as its element type, and the other values read back as nil
    # (see the README's Spinel notes). Choosing here, in one variable,
    # keeps the result mixed.
    def self.id_or_new(doc)
      id = Collection.id_of(doc)
      id = BSON::ObjectId.new if id.nil?
      id
    end

    def write_command(verb, ordered)
      cmd = BSON::Document.new
      cmd[verb] = @name
      cmd["ordered"] = ordered
      cmd["$db"] = @database.name
      cmd
    end

    def update_command(filter, update, multi, upsert)
      stmt = BSON::Document.new
      stmt["q"] = filter.nil? ? BSON::Document.new : filter
      stmt["u"] = update
      stmt["multi"] = true if multi
      stmt["upsert"] = true if upsert
      reply = connection.command_seq(write_command("update", true), "updates", [stmt])
      Mongo::Operation::Update::Result.new(reply)
    end

    def delete_command(filter, limit)
      stmt = BSON::Document.new
      stmt["q"] = filter.nil? ? BSON::Document.new : filter
      stmt["limit"] = limit
      reply = connection.command_seq(write_command("delete", true), "deletes", [stmt])
      Mongo::Operation::Delete::Result.new(reply)
    end
  end
end
