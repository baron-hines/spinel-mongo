# Mongo::Database: a name on a client, with command for anything the
# collection API doesn't cover.
require "bson"
require "mongo/results"
require "mongo/cursor"
require "mongo/collection"

module Mongo
  class Database
    def initialize(client, name)
      @client = client
      @name = name
    end

    def name
      @name
    end

    def client
      @client
    end

    def [](name)
      Mongo::Collection.new(self, name.to_s)
    end

    def collection(name)
      self[name]
    end

    # Runs one command on this database and returns its reply in a
    # Mongo::Operation::Result. A failed reply raises OperationFailure,
    # as the gem's does.
    def command(cmd, opts = {})
      doc = BSON::Document.new
      cmd.each { |k, v| doc[k.to_s] = v }
      doc["$db"] = @name
      Mongo::Operation::Result.new(@client.server.connection.command(doc))
    end

    # The names of the collections, without the system ones, as the gem
    # lists them.
    def collection_names(opts = {})
      cmd = BSON::Document.new
      cmd["listCollections"] = 1
      cmd["cursor"] = BSON::Document.new
      cmd["nameOnly"] = true
      cmd["$db"] = @name
      conn = @client.server.connection
      names = []
      Mongo::Cursor.new(conn, @name, conn.command(cmd), 0, 0).each do |doc|
        n = doc["name"]
        if n.is_a?(String) && !n.start_with?("system.") && !n.include?("$")
          names.push(n)
        end
      end
      names
    end
  end
end
