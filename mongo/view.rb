# Mongo::Collection::View: what find returns. It holds the filter and
# the options and sends nothing until it is iterated. sort, limit, skip,
# projection and batch_size return a new view, as the gem's do.
require "bson"
require "mongo/cursor"

module Mongo
  class Collection
    class View
      # options: sort, projection, limit, skip and batch_size, as find
      # takes them.
      def initialize(collection, filter, options = {})
        @collection = collection
        @filter = filter
        @sort = BSON::Document.new
        @projection = BSON::Document.new
        @limit = 0
        @skip = 0
        @batch_size = 0
        sort = options[:sort]
        @sort = sort if sort.is_a?(Hash)
        projection = options[:projection]
        @projection = projection if projection.is_a?(Hash)
        limit = options[:limit]
        @limit = limit if limit.is_a?(Integer)
        skip = options[:skip]
        @skip = skip if skip.is_a?(Integer)
        batch_size = options[:batch_size]
        @batch_size = batch_size if batch_size.is_a?(Integer)
      end

      def collection
        @collection
      end

      def filter
        @filter
      end

      def sort(spec)
        v = copy
        v.set_sort(spec)
        v
      end

      def projection(spec)
        v = copy
        v.set_projection(spec)
        v
      end

      # A negative limit asks for one batch of at most that many, as in
      # the gem.
      def limit(n)
        v = copy
        v.set_numbers(n, @skip, @batch_size)
        v
      end

      def skip(n)
        v = copy
        v.set_numbers(@limit, n, @batch_size)
        v
      end

      def batch_size(n)
        v = copy
        v.set_numbers(@limit, @skip, n)
        v
      end

      def copy
        v = View.new(@collection, @filter, {})
        v.set_sort(@sort)
        v.set_projection(@projection)
        v.set_numbers(@limit, @skip, @batch_size)
        v
      end

      def set_sort(spec)
        @sort = spec
        nil
      end

      def set_projection(spec)
        @projection = spec
        nil
      end

      def set_numbers(limit, skip, batch_size)
        @limit = limit
        @skip = skip
        @batch_size = batch_size
        nil
      end

      # The find command, with the gem's fields in the gem's order.
      def find_command
        cmd = BSON::Document.new
        cmd["find"] = @collection.name
        limit = @limit < 0 ? -@limit : @limit
        if @batch_size > 0
          cmd["batchSize"] = limit > 0 && limit < @batch_size ? limit : @batch_size
        end
        cmd["filter"] = @filter
        cmd["limit"] = limit if limit > 0
        cmd["projection"] = @projection if @projection.length > 0
        cmd["singleBatch"] = true if @limit < 0
        cmd["skip"] = @skip if @skip > 0
        cmd["sort"] = @sort if @sort.length > 0
        cmd["$db"] = @collection.database.name
        cmd
      end

      # Sends find, yields each document, and sends getMore for the rest.
      # A block that breaks out closes the server's cursor.
      def each
        conn = @collection.connection
        reply = conn.command(find_command)
        limit = @limit < 0 ? -@limit : @limit
        Mongo::Cursor.new(conn, @collection.database.name, reply, @batch_size, limit).each { |doc| yield doc }
        nil
      end

      # The first document, or nil. As in the gem, this is a plain find
      # that stops after one document, not a find with limit 1.
      def first
        each { |doc| return doc }
        nil
      end

      def to_a
        docs = []
        each { |doc| docs.push(doc) }
        docs
      end

      # The view's filter counted, with skip and limit from opts. The
      # view's own skip and limit don't apply, as in the gem.
      def count_documents(opts = {})
        @collection.count_documents(@filter, opts)
      end
    end
  end
end
