# Mongo::Client, the gem's entry point: one server, given as a mongodb://
# URI or as ["host:port"], and the options a program passes it. The
# connection is opened on first use, not here, as the gem connects in the
# background.
require "mongo/errors"
require "mongo/uri"
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
    # A URI's options come first and options given here override them,
    # as in the gem. The URI's hosts, user, password and database go in
    # as the matching options.
    #
    # shared is internal: Client#use passes its Server so the new client
    # shares the connection.
    def initialize(addresses_or_uri, options = {}, shared = nil)
      hosts = []
      if addresses_or_uri.is_a?(String)
        uri = Mongo::URI.get(addresses_or_uri)
        hosts = uri.servers
        options = Client.layer(uri.client_options, options)
      else
        addresses_or_uri.each { |a| hosts.push(a.to_s) }
      end
      if hosts.length != 1
        raise ArgumentError, "spinel-mongo connects to one server; give one host, not " + hosts.length.to_s +
                             " (seed lists of several come in v0.2)"
      end
      if options[:ssl] == true || options[:tls] == true
        raise ArgumentError, "spinel-mongo doesn't do TLS yet; v0.2 adds it behind require \"mongo/tls\""
      end
      Client.check_auth(options)
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

    # Options from a URI with the program's on top. Not named merge: a
    # class method by that name is called with one argument once compiled
    # (Spinel 7181da6; see the README's Spinel notes).
    def self.layer(base, over)
      opts = {}
      base.each { |k, v| opts[k] = v }
      over.each { |k, v| opts[k] = v }
      opts
    end

    # The gem's checks of the credentials, made before connecting, with
    # its messages. A mechanism other than SCRAM's two raises
    # InvalidMechanism.
    def self.check_auth(options)
      user = options[:user]
      source = options[:auth_source]
      mech = options[:auth_mech]
      if mech.nil?
        if !user.nil? && user.to_s == ""
          raise Mongo::Auth::InvalidConfiguration, "Empty username is not supported for default auth mechanism"
        end
        if !source.nil? && source.to_s == ""
          raise Mongo::Auth::InvalidConfiguration, "Auth source cannot be empty for default auth mechanism"
        end
        return nil
      end
      Client.mechanism(mech)
      name = mech.to_s
      raise Mongo::Auth::InvalidConfiguration, "Username is required for auth mechanism " + name if user.nil?
      if options[:password].nil?
        raise Mongo::Auth::InvalidConfiguration, "Password is required for auth mechanism " + name
      end
      if !source.nil? && source.to_s == ""
        raise Mongo::Auth::InvalidConfiguration, "Auth source cannot be empty for auth mechanism " + name
      end
      nil
    end

    def self.open_server(host, options, database_name, connector)
      if host.start_with?("/") || host.end_with?(".sock")
        raise ArgumentError, "spinel-mongo doesn't connect over UNIX domain sockets: " + host
      end
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
          port = host[colon + 1, host.length - colon - 1].to_i if colon + 1 < host.length
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
