# What operations return, under the gem's class names and with the
# gem's readers. Mongo::Operation::Result wraps a command's reply (the
# gem's wraps every reply of an operation; here there is always one).
# insert_one, the updates and the deletes return its subclasses, and
# insert_many returns a Mongo::BulkWrite::Result built from its batches.
require "bson"

module Mongo
  module Operation
    class Result
      def initialize(reply)
        @reply = reply
      end

      # The replies, as the gem's Result#documents gives them.
      def documents
        [@reply]
      end

      def first
        @reply
      end

      def ok?
        @reply["ok"] == 1
      end

      # The reply's n: how many documents the write touched.
      def n
        v = @reply["n"]
        v.is_a?(Integer) ? v : 0
      end
    end

    class Insert
      class Result < Mongo::Operation::Result
        def initialize(reply, ids)
          super(reply)
          @ids = ids
        end

        def inserted_id
          @ids[0]
        end

        def inserted_ids
          @ids
        end
      end
    end

    class Update
      class Result < Mongo::Operation::Result
        # Documents that matched the filter. An upsert inserted rather
        # than matched, so it counts 0 here, as in the gem.
        def matched_count
          n - upserted_count
        end

        def modified_count
          v = @reply["nModified"]
          v.is_a?(Integer) ? v : 0
        end

        def upserted_count
          up = @reply["upserted"]
          up.is_a?(Array) ? up.length : 0
        end

        # The _id of the document an upsert inserted, or nil.
        def upserted_id
          up = @reply["upserted"]
          return nil unless up.is_a?(Array) && up.length > 0
          first = up[0]
          first.is_a?(Hash) ? first["_id"] : nil
        end
      end
    end

    class Delete
      class Result < Mongo::Operation::Result
        def deleted_count
          n
        end
      end
    end
  end

  class BulkWrite
    # The combined result of insert_many's batches: "n_inserted", "n" and
    # "inserted_ids", and on failure "writeErrors" or "writeConcernErrors",
    # the Hash the gem's BulkWriteError carries as its result.
    class Result
      def initialize(results)
        @results = results
      end

      def inserted_count
        @results["n_inserted"]
      end

      def inserted_ids
        @results["inserted_ids"]
      end

      # insert_many touches none of these; they are nil, as in the gem.
      def deleted_count
        @results["n_removed"]
      end

      def matched_count
        @results["n_matched"]
      end

      def modified_count
        @results["n_modified"]
      end

      def upserted_count
        @results["n_upserted"]
      end

      def upserted_ids
        []
      end
    end
  end
end
