# Mongo::URI: the gem's reading of a mongodb:// connection string, for
# the hosts, credentials, database and options this driver uses. It
# checks the string the way the gem does and raises the gem's
# Mongo::Error::InvalidURI with the gem's messages. Options the driver
# doesn't use are skipped, as the gem skips ones it doesn't know, but
# without the gem's logged warning.
#
# mongodb+srv:// needs DNS SRV lookups, which spinel-mongo doesn't do
# yet, and raises InvalidURI saying so.
require "mongo/errors"

module Mongo
  class URI
    FORMAT = Mongo::Error::InvalidURI::FORMAT
    UNESCAPED_USER_PWD = "User name and password must be urlencoded."
    UNESCAPED_DATABASE = "Auth database must be urlencoded."

    # The URI's servers as written, its credentials and database (nil
    # when not given), and its options under the gem's Ruby names:
    # auth_source, auth_mech, app_name, connect_timeout and
    # socket_timeout (in seconds), direct_connection, and ssl (from tls
    # or ssl).
    def self.get(string)
      raise Mongo::Error::InvalidURI.new("", "URI must be a string, not nil.") if string.nil?
      raise Mongo::Error::InvalidURI.new(string, "Cannot parse an empty URI.") if string == ""
      scheme = URI.before(string, "://")
      if scheme == "mongodb+srv"
        raise Mongo::Error::InvalidURI.new(string, "spinel-mongo doesn't read mongodb+srv URIs yet, as they need " \
                                                   "DNS SRV lookups; give the hosts in a mongodb:// URI instead")
      end
      unless scheme == "mongodb"
        raise Mongo::Error::InvalidURI.new(string, "Invalid scheme '" + scheme +
                                                   "'. Scheme must be 'mongodb' or 'mongodb+srv'")
      end
      URI.new(string)
    end

    def initialize(string)
      raise Mongo::Error::InvalidURI.new("", "URI must be a string, not nil.") if string.nil?
      raise Mongo::Error::InvalidURI.new(string, "Cannot parse an empty URI.") if string == ""
      @string = string
      @servers = []
      @user = nil
      @password = nil
      @database = nil
      @uri_options = {}
      @ssl = []
      scheme = URI.before(string, "://")
      unless scheme == "mongodb"
        invalid("Invalid scheme '" + scheme + "'. Scheme must be 'mongodb'. Use URI#get to parse SRV URIs.")
      end
      remaining = URI.after(string, "://")
      invalid("No hosts in the URI") if remaining == ""
      parse(remaining)
      validate
    end

    def servers
      @servers
    end

    def user
      @user
    end

    def password
      @password
    end

    def uri_options
      @uri_options
    end

    def credentials
      { user: @user, password: @password }
    end

    # The database named in the URI, or "admin".
    def database
      @database.nil? ? "admin" : @database
    end

    # The options Client.new takes from the URI: the URI's options, its
    # database when it names one, and its credentials when it has a user.
    def client_options
      opts = {}
      @uri_options.each { |k, v| opts[k] = v }
      opts[:database] = @database unless @database.nil?
      unless @user.nil?
        opts[:user] = @user
        opts[:password] = @password
      end
      opts
    end

    def parse(remaining)
      q = remaining.index("?")
      hosts_and_db = q.nil? ? remaining : remaining[0, q]
      options = q.nil? ? nil : remaining[q + 1, remaining.length - q - 1]
      if !options.nil? && options.include?("?")
        invalid("Options contain an unescaped question mark (?), or the database name contains a question mark and was not escaped")
      end
      s = hosts_and_db.index("/")
      hosts = s.nil? ? hosts_and_db : hosts_and_db[0, s]
      db = s.nil? ? nil : hosts_and_db[s + 1, hosts_and_db.length - s - 1]
      invalid("Database name contains an unescaped slash (/): " + db) if !db.nil? && db.include?("/")
      creds = nil
      at = hosts.index("@")
      unless at.nil?
        creds = hosts[0, at]
        hosts = hosts[at + 1, hosts.length - at - 1]
        invalid("Empty hosts list") if hosts == ""
        invalid("Unescaped @ in auth info") if hosts.include?("@")
      end
      invalid("Missing host; at least one must be provided") if hosts == ""
      URI.split(hosts, ",").each do |host|
        invalid("Empty host given in the host list") if host == ""
        decoded = URI.decode(host)
        problem = URI.address_problem(decoded)
        invalid(problem) unless problem == ""
        @servers.push(decoded)
      end
      unless creds.nil?
        @user = parse_credential(URI.before(creds, ":"))
        pwd = URI.after(creds, ":")
        @password = parse_credential(pwd) unless pwd == ""
      end
      unless options.nil?
        URI.split(options, "&").each do |option|
          next if option == ""
          eq = option.index("=")
          invalid("Option " + option + " has no value") if eq.nil?
          add_option(URI.decode(option[0, eq]), URI.decode(option[eq + 1, option.length - eq - 1]))
        end
      end
      unless db.nil?
        invalid(UNESCAPED_DATABASE) if URI.unsafe?(db)
        @database = URI.decode(db) unless db == ""
      end
      nil
    end

    def parse_credential(text)
      invalid(UNESCAPED_USER_PWD) if URI.unsafe?(text)
      decoded = URI.decode(text)
      invalid(UNESCAPED_USER_PWD) if decoded.include?("%") && URI.encode(decoded) != text
      decoded
    end

    # One option, under the gem's name and converted as the gem converts
    # it. A value the gem would warn about and drop is dropped; an option
    # given twice keeps its first value, as in the gem.
    def add_option(key, value)
      name = key.downcase
      if name == "tls" || name == "ssl"
        @ssl.push(URI.bool(value))
        return nil
      end
      sym = :none
      v = nil
      if name == "authsource"
        sym = :auth_source
        v = value
      elsif name == "authmechanism"
        sym = :auth_mech
        v = URI.mechanism(value)
      elsif name == "appname"
        sym = :app_name
        v = value
      elsif name == "connecttimeoutms"
        sym = :connect_timeout
        v = URI.ms(value)
      elsif name == "sockettimeoutms"
        sym = :socket_timeout
        v = URI.ms(value)
      elsif name == "directconnection"
        sym = :direct_connection
        v = URI.bool(value)
      end
      @uri_options[sym] = v unless sym == :none || v.nil? || @uri_options.key?(sym)
      nil
    end

    def validate
      if @ssl.length > 0
        if @ssl.include?(nil)
          invalid_no_format("invalid boolean value for 'tls' or 'ssl'; only 'true' and 'false' are accepted")
        end
        if @ssl.include?(true) && @ssl.include?(false)
          invalid_no_format("all instances of 'tls' and 'ssl' must have the same value")
        end
        @uri_options[:ssl] = @ssl[0]
      end
      if @uri_options[:direct_connection] == true && @servers.length > 1
        invalid_no_format("directConnection=true cannot be used with multiple seeds")
      end
      nil
    end

    def invalid(details)
      raise Mongo::Error::InvalidURI.new(@string, details, FORMAT)
    end

    def invalid_no_format(details)
      raise Mongo::Error::InvalidURI.new(@string, details)
    end

    # The string with its credentials hidden, as in error messages.
    def self.redact(string)
      Mongo::Error::InvalidURI.redact(string)
    end

    # What the gem's Address::Validator says is wrong with a host, or "".
    def self.address_problem(address)
      if address.start_with?("[")
        close = address.index("]")
        if !close.nil? && close > 1 && URI.only?(address[1, close - 1], "0123456789:")
          rest = address[close + 1, address.length - close - 1]
          return "" if rest == ""
          if rest.start_with?(":") && rest.length > 1 && URI.only?(rest[1, rest.length - 1], "0123456789")
            return URI.port_problem(rest[1, rest.length - 1])
          end
        end
      end
      return "" if address.start_with?("/") || address.end_with?(".sock")
      if address.include?("/") || address.include?("[") || address.include?("]")
        return "Invalid hostname: " + address
      end
      colon = address.index(":")
      if !colon.nil? && address.index(":", colon + 1)
        return "Multiple port delimiters are not allowed: " + address
      end
      parts = URI.split(address, ":")
      host = parts.length > 0 ? parts[0] : ""
      return "Host is empty: " + address if host == ""
      return "Hostname cannot start with a dot: " + host if host.start_with?(".")
      return "Hostname cannot end with a dot: " + host if host.end_with?(".")
      return "Runs of multiple dots are not allowed in hostname: " + host if host.include?("..")
      return "" if parts.length < 2
      URI.port_problem(parts[1])
    end

    def self.port_problem(port)
      n = port.to_i
      return "" if port.length > 0 && n > 0 && n <= 65_535
      "Invalid port: " + port + ". Port must be an integer greater than 0 and less than 65536"
    end

    def self.only?(text, allowed)
      i = 0
      while i < text.length
        return false unless allowed.include?(text[i])
        i += 1
      end
      true
    end

    # A user, password or database holding :, / or @ unescaped.
    def self.unsafe?(text)
      text.include?(":") || text.include?("/") || text.include?("@")
    end

    # text split on sep with trailing empty pieces dropped, as Ruby's
    # String#split without a limit.
    def self.split(text, sep)
      parts = []
      start = 0
      while true
        i = text.index(sep, start)
        if i.nil?
          parts.push(text[start, text.length - start])
          break
        end
        parts.push(text[start, i - start])
        start = i + sep.length
      end
      parts.pop while parts.length > 0 && parts[parts.length - 1] == ""
      parts
    end

    # The part of text before the first sep, or all of it.
    def self.before(text, sep)
      i = text.index(sep)
      i.nil? ? text : text[0, i]
    end

    # The part of text after the first sep, or "".
    def self.after(text, sep)
      i = text.index(sep)
      i.nil? ? "" : text[i + sep.length, text.length - i - sep.length]
    end

    # %XX sequences decoded; a % not followed by two hex digits is kept.
    def self.decode(text)
      return text unless text.include?("%")
      src = text.b
      out = "".b
      i = 0
      n = src.bytesize
      while i < n
        if src.getbyte(i) == 37 && i + 2 < n && URI.hex?(src.getbyte(i + 1)) && URI.hex?(src.getbyte(i + 2))
          out << [src.byteslice(i + 1, 2)].pack("H2")
          i += 3
        else
          out << src.byteslice(i, 1)
          i += 1
        end
      end
      out.force_encoding("UTF-8")
    end

    def self.hex?(b)
      (b >= 48 && b <= 57) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102)
    end

    # CGI.escape with spaces as %20, which the gem uses to check that a
    # decoded user or password holding % was escaped in full.
    def self.encode(text)
      src = text.b
      out = "".b
      i = 0
      while i < src.bytesize
        b = src.getbyte(i)
        if (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) ||
           b == 45 || b == 46 || b == 95 || b == 126
          out << src.byteslice(i, 1)
        else
          out << "%" << src.byteslice(i, 1).unpack1("H*").upcase
        end
        i += 1
      end
      out
    end

    def self.bool(value)
      return true if value == "true" || value == "TRUE"
      return false if value == "false" || value == "FALSE"
      nil
    end

    # Milliseconds as seconds, or nil for a value the gem drops: one that
    # isn't a plain decimal number, or is negative.
    def self.ms(value)
      text = value
      text = text[1, text.length - 1] if text.start_with?("-")
      dot = text.index(".")
      whole = dot.nil? ? text : text[0, dot]
      frac = dot.nil? ? "0" : text[dot + 1, text.length - dot - 1]
      return nil if whole == "" || frac == ""
      return nil unless URI.only?(whole, "0123456789") && URI.only?(frac, "0123456789")
      return nil if value.start_with?("-")
      value.to_f / 1000
    end

    # authMechanism as the gem's symbol, or the text when it isn't one
    # the gem knows.
    def self.mechanism(value)
      v = value.upcase
      return :scram256 if v == "SCRAM-SHA-256"
      return :scram if v == "SCRAM-SHA-1"
      return :plain if v == "PLAIN"
      return :gssapi if v == "GSSAPI"
      return :aws if v == "MONGODB-AWS"
      return :mongodb_cr if v == "MONGODB-CR"
      return :mongodb_x509 if v == "MONGODB-X509"
      value
    end
  end
end
