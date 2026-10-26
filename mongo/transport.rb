# The real transport: a TCP connection to a server over sp_net, with the
# duck Mongo::Connection talks to (write, read_some, close). Tests give
# the connection a scripted transport with the same methods instead.
require "mongo/sock"
require "mongo/errors"

module Mongo
  class Transport
    # connect_timeout and socket_timeout are in seconds, as the gem's
    # options of the same names; nil waits forever. The gem's defaults
    # are 10 seconds to connect and no limit on reads. A refused or
    # timed-out connect raises NoServerAvailable at once.
    def initialize(host, port, connect_timeout = 10.0, socket_timeout = nil)
      @address = host + ":" + port.to_s
      @socket_timeout = socket_timeout.nil? ? -1.0 : socket_timeout.to_f
      limit = connect_timeout.nil? ? -1.0 : connect_timeout.to_f
      @fd = MongoSock.sp_net_connect_timeout(host, port, limit)
      if @fd < 0
        if MongoSock.sp_net_take_connect_timeout == 1
          raise Mongo::Error::NoServerAvailable, "No server is available at " + @address +
                                                 ": no connection within " + limit.to_s + " seconds"
        end
        raise Mongo::Error::NoServerAvailable, "No server is available at " + @address +
                                               ": the connection was refused"
      end
    end

    # "host:port", for error messages.
    def address
      @address
    end

    # The socket's fd, -1 once closed.
    def fd
      @fd
    end

    def write(bytes)
      if @fd < 0 || MongoSock.sp_net_write_bytes(@fd, bytes, bytes.bytesize) < 0
        close
        raise Mongo::Error::SocketError, "Could not write to " + @address
      end
      nil
    end

    # Up to max bytes, or "" when the server has closed the connection.
    # A read that runs past socket_timeout closes the socket and raises
    # SocketTimeoutError.
    def read_some(max)
      return "".b if @fd < 0
      chunk = MongoSock.sp_net_recv_some_timeout(@fd, max, @socket_timeout)
      if chunk.bytesize == 0 && MongoSock.sp_net_take_recv_timeout == 1
        close
        raise Mongo::Error::SocketTimeoutError, "Took more than " + @socket_timeout.to_s +
                                                " seconds to receive data (for " + @address + ")"
      end
      chunk
    end

    # Whether the server has closed the connection, found without
    # waiting: a read with no deadline left that finds nothing to read
    # means it is open. Called only between round trips, so a byte read
    # here is one nothing asked for, and the connection is no good.
    def peer_closed?
      return true if @fd < 0
      chunk = MongoSock.sp_net_recv_some_timeout(@fd, 1, 0.0)
      return false if chunk.bytesize == 0 && MongoSock.sp_net_take_recv_timeout == 1
      true
    end

    def close
      if @fd >= 0
        MongoSock.sp_net_close(@fd)
        @fd = -1
      end
      nil
    end
  end
end

module Mongo
  # Opens a Mongo::Transport for Mongo::Server. Client#default_connector
  # is defined here, with the transport, so the rest of the client runs
  # under CRuby too, where tests define their own.
  class Connector
    def open(host, port, connect_timeout, socket_timeout)
      Mongo::Transport.new(host, port, connect_timeout, socket_timeout)
    end
  end

  class Client
    def default_connector
      Mongo::Connector.new
    end
  end
end
