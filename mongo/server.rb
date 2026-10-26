# The one server a client talks to, and its one connection. The
# connection is opened on first use (connect, hello, then SCRAM when
# there are credentials) and opened again for the next command after it
# breaks. Clients made with Client#use share their Server, so they share
# the connection, as the gem's share their cluster.
#
# A Mutex guards opening the connection, so threads that share a client
# share one connection. Before each use the connection is checked: one
# the server has closed since its last reply (a restart, an idle
# timeout) is replaced before anything is sent on it, and so is one
# inherited across a fork, whose socket belongs to the parent.
#
# Connecting goes through a connector duck, open(host, port,
# connect_timeout, socket_timeout), which returns a transport. On Spinel
# that is Mongo::Connector, in mongo/transport.rb; tests pass their own.
require "mongo/connection"

module Mongo
  class Server
    def initialize(connector, host, port, app_name, connect_timeout, socket_timeout,
                   user, password, database, auth_source, mechanism)
      @connector = connector
      @host = host
      @port = port
      @app_name = app_name
      @connect_timeout = connect_timeout
      @socket_timeout = socket_timeout
      @user = user
      @password = password
      @database = database
      @auth_source = auth_source
      @mechanism = mechanism
      @connection = nil
      @lock = Mutex.new
      @pid = Process.pid
    end

    # "host:port".
    def address
      @host + ":" + @port.to_s
    end

    # The open connection, or a new one when there is none or the last
    # one broke. A failed handshake or login raises, and the next call
    # tries again.
    def connection
      @lock.lock
      begin
        c = @connection
        # After a fork, closing the child's copy of the socket sends
        # nothing, so the parent's connection is left as it was.
        c.close if !c.nil? && (@pid != Process.pid || c.stale?)
        return c if !c.nil? && !c.closed?
        @connection = nil
        @pid = Process.pid
        transport = @connector.open(@host, @port, @connect_timeout, @socket_timeout)
        c = Mongo::Connection.new(transport, address)
        c.handshake(@app_name, @user == "" ? "" : @auth_source + "." + @user)
        c.authenticate(@user, @password, @database, @auth_source, @mechanism) if @user != ""
        @connection = c
        c
      ensure
        @lock.unlock
      end
    end

    def close
      @lock.lock
      begin
        c = @connection
        c.close unless c.nil?
        @connection = nil
      ensure
        @lock.unlock
      end
      nil
    end
  end
end
