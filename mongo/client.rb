# Mongo::Client, the gem's entry point: one server, given as
# ["host:port"], and the options a program passes it. The connection is
# opened on first use, not here, as the gem connects in the background.
# URI strings arrive with mongo/uri.rb.
require "mongo/errors"
require "mongo/server"
require "mongo/database"

module Mongo
  class Client
    DEFAULT_PORT = 27017

    # options, as the gem's: database (default "admin"), user, password,
    # auth_source (default the database option, then "admin"), auth_mech
    # (:scram256 or :scram; by default chosen from the server's list),
    # app_name, connect_timeout (default 10 seconds) and socket_timeout
    # (default none). The gem's other options are ignored.
    # direct_connection is always so, since there is one server.
    #
    # shared is internal: Client#use passes its Server so the new client
    # shares the connection.
    def initialize(hosts, options = {}, shared = nil)
      if hosts.length != 1
        raise ArgumentError, "spinel-mongo connects to one server; give one \"host:port\", not " +
                             hosts.length.to_s
      end
      @hosts = hosts
      @options = options
      db = options[:database]
      @database_name = db.nil? ? "admin" : db.to_s
      if shared.nil?
        @server = Client.open_server(hosts[0], options, @database_name, default_connector)
      else
        @server = shared
      end
    end

    def self.open_server(host, options, database_name, connector)
      name = host
      port = DEFAULT_PORT
      if host.start_with?("[")
        close = host.index("]")
        raise ArgumentError, "Invalid address: " + host if close.nil?
        name = host[1, close - 1]
        rest = host[close + 1, host.length - close - 1]
        port = rest[1, rest.length - 1].to_i if rest.start_with?(":")
      else
        colon = host.index(":")
        unless colon.nil?
          name = host[0, colon]
          port = host[colon + 1, host.length - colon - 1].to_i
        end
      end
      Mongo::Server.new(connector, name, port, Client.text(options[:app_name]),
                        Client.seconds(options[:connect_timeout], 10.0),
                        Client.seconds(options[:socket_timeout], -1.0),
                        Client.text(options[:user]), Client.text(options[:password]),
                        database_name, Client.auth_source(options, database_name),
                        Client.mechanism(options[:auth_mech]))
    end

    def self.text(v)
      v.nil? ? "" : v.to_s
    end

    # A timeout option in seconds, or default when it isn't given; -1.0
    # means none.
    def self.seconds(v, default)
      return default if v.nil?
      return v.to_f if v.is_a?(Float) || v.is_a?(Integer)
      default
    end

    def self.auth_source(options, database_name)
      source = options[:auth_source]
      source.nil? ? database_name : source.to_s
    end

    # The SCRAM name of the gem's auth_mech symbol, or "" to choose.
    def self.mechanism(v)
      return "" if v.nil?
      return Mongo::Scram::SHA256 if v == :scram256
      return Mongo::Scram::SHA1 if v == :scram
      raise Mongo::Auth::InvalidMechanism.new(v.inspect)
    end

    # The Database named by the database option.
    def database
      Mongo::Database.new(self, @database_name)
    end

    # A collection of the client's database.
    def [](name)
      database[name]
    end

    # A client for another database, on the same connection.
    def use(name)
      c = Client.new(@hosts, @options, @server)
      c.switch_database(name.to_s)
      c
    end

    def switch_database(name)
      @database_name = name
      nil
    end

    # Closes the connection. The client opens a new one if it is used
    # again, as the gem's does.
    def close
      @server.close
      true
    end

    # The Server, for Database and Collection.
    def server
      @server
    end
  end
end
