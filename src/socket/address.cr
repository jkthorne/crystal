require "./common"
require "uri"

class Socket
  abstract struct Address
    getter family : Family
    getter size : Int32

    # Returns either an `IPAddress` or `UNIXAddress` from the internal OS
    # representation. Only INET, INET6 and UNIX families are supported.
    def self.from(sockaddr : LibC::Sockaddr*, addrlen) : Address
      case family = Family.new(sockaddr.value.sa_family)
      when Family::INET6
        IPAddress.new(sockaddr.as(LibC::SockaddrIn6*), addrlen.to_i)
      when Family::INET
        IPAddress.new(sockaddr.as(LibC::SockaddrIn*), addrlen.to_i)
      when Family::UNIX
        UNIXAddress.new(sockaddr.as(LibC::SockaddrUn*), addrlen.to_i)
      else
        raise "Unsupported family type: #{family} (#{family.value})"
      end
    end

    # Parses a `Socket::Address` from an URI.
    #
    # Supported formats:
    # * `ip://<host>:<port>`
    # * `tcp://<host>:<port>`
    # * `udp://<host>:<port>`
    # * `unix://<path>`
    #
    # See `IPAddress.parse` and `UNIXAddress.parse` for details.
    def self.parse(uri : URI) : self
      case uri.scheme
      when "ip", "tcp", "udp"
        IPAddress.parse uri
      when "unix"
        UNIXAddress.parse uri
      else
        raise Socket::Error.new "Unsupported address type: #{uri.scheme}"
      end
    end

    # :ditto:
    def self.parse(uri : String) : self
      parse URI.parse(uri)
    end

    def initialize(@family : Family, @size : Int32)
    end

    abstract def to_unsafe : LibC::Sockaddr*
  end

  # IP address representation.
  #
  # Holds a binary representation of an IP address, either translated from a
  # `String`, or directly received from an opened connection (e.g.
  # `Socket#local_address`, `Socket#receive`).
  #
  # Example:
  # ```
  # require "socket"
  #
  # Socket::IPAddress.new("127.0.0.1", 8080)
  # Socket::IPAddress.new("fe80::2ab2:bdff:fe59:8e2c", 1234)
  # ```
  #
  # `IPAddress` won't resolve domains, including `localhost`. If you must
  # resolve an IP, or don't know whether a `String` contains an IP or a domain
  # name, you should use `Addrinfo.resolve` instead.
  struct IPAddress < Address
    UNSPECIFIED  = "0.0.0.0"
    UNSPECIFIED6 = "::"
    LOOPBACK     = "127.0.0.1"
    LOOPBACK6    = "::1"
    BROADCAST    = "255.255.255.255"
    BROADCAST6   = "ff0X::1"

    getter port : Int32

    @addr : LibC::In6Addr | LibC::InAddr

    def initialize(@address : String, @port : Int32)
      if addr = IPAddress.address_v6?(address)
        @addr = addr
        @family = Family::INET6
        @size = sizeof(LibC::SockaddrIn6)
      elsif addr = IPAddress.address_v4?(address)
        @addr = addr
        @family = Family::INET
        @size = sizeof(LibC::SockaddrIn)
      else
        raise Error.new("Invalid IP address: #{address}")
      end
    end

    # Creates an `IPAddress` from the internal OS representation. Supports both
    # INET and INET6 families.
    def self.from(sockaddr : LibC::Sockaddr*, addrlen) : IPAddress
      case family = Family.new(sockaddr.value.sa_family)
      when Family::INET6
        new(sockaddr.as(LibC::SockaddrIn6*), addrlen.to_i)
      when Family::INET
        new(sockaddr.as(LibC::SockaddrIn*), addrlen.to_i)
      else
        raise "Unsupported family type: #{family} (#{family.value})"
      end
    end

    # Parses a `Socket::IPAddress` from an URI.
    #
    # It expects the URI to include `<scheme>://<host>:<port>` where `scheme` as
    # well as any additional URI components (such as `path` or `query`) are ignored.
    #
    # `host` must be an IP address (v4 or v6), otherwise `Socket::Error` will be
    # raised. Domain names will not be resolved.
    #
    # ```
    # require "socket"
    #
    # Socket::IPAddress.parse("tcp://127.0.0.1:8080") # => Socket::IPAddress.new("127.0.0.1", 8080)
    # Socket::IPAddress.parse("udp://[::1]:8080")     # => Socket::IPAddress.new("::1", 8080)
    # ```
    def self.parse(uri : URI) : IPAddress
      host = uri.host.presence
      raise Socket::Error.new("Invalid IP address: missing host") unless host

      port = uri.port
      raise Socket::Error.new("Invalid IP address: missing port") unless port

      # remove ipv6 brackets
      if host.starts_with?('[') && host.ends_with?(']')
        host = host.byte_slice(1, host.bytesize - 2)
      end

      new(host, port)
    end

    # :ditto:
    def self.parse(uri : String) : self
      parse URI.parse(uri)
    end

    protected def initialize(sockaddr : LibC::SockaddrIn6*, @size)
      @family = Family::INET6
      @addr = sockaddr.value.sin6_addr
      @port =
        {% if flag?(:dragonfly) %}
          Intrinsics.bswap16(sockaddr.value.sin6_port).to_i
        {% else %}
          LibC.ntohs(sockaddr.value.sin6_port).to_i
        {% end %}
    end

    protected def initialize(sockaddr : LibC::SockaddrIn*, @size)
      @family = Family::INET
      @addr = sockaddr.value.sin_addr
      @port =
        {% if flag?(:dragonfly) %}
          Intrinsics.bswap16(sockaddr.value.sin_port).to_i
        {% else %}
          LibC.ntohs(sockaddr.value.sin_port).to_i
        {% end %}
    end

    # Returns `true` if *address* is a valid IPv4 or IPv6 address.
    def self.valid?(address : String) : Bool
      valid_v4?(address) || valid_v6?(address)
    end

    # Returns `true` if *address* is a valid IPv4 address.
    def self.valid_v6?(address : String) : Bool
      !address_v6?(address).nil?
    end

    # :nodoc:
    protected def self.address_v6?(address : String)
      addr = uninitialized LibC::In6Addr
      addr if LibC.inet_pton(LibC::AF_INET6, address, pointerof(addr)) == 1
    end

    # Returns `true` if *address* is a valid IPv5 address.
    def self.valid_v4?(address : String) : Bool
      !address_v4?(address).nil?
    end

    # :nodoc:
    protected def self.address_v4?(address : String)
      addr = uninitialized LibC::InAddr
      addr if LibC.inet_pton(LibC::AF_INET, address, pointerof(addr)) == 1
    end

    # Returns a `String` representation of the IP address.
    #
    # Example:
    # ```
    # ip_address = socket.remote_address
    # ip_address.address # => "127.0.0.1"
    # ```
    getter(address : String) { address(@addr) }

    private def address(addr : LibC::In6Addr)
      String.new(46) do |buffer|
        unless LibC.inet_ntop(family, pointerof(addr).as(Void*), buffer, 46)
          raise Socket::Error.from_errno("Failed to convert IP address")
        end
        {LibC.strlen(buffer), 0}
      end
    end

    private def address(addr : LibC::InAddr)
      String.new(16) do |buffer|
        unless LibC.inet_ntop(family, pointerof(addr).as(Void*), buffer, 16)
          raise Socket::Error.from_errno("Failed to convert IP address")
        end
        {LibC.strlen(buffer), 0}
      end
    end

    # Returns `true` if this IP is a loopback address.
    #
    # In the IPv4 family, loopback addresses are all addresses in the subnet
    # `127.0.0.0/24`. In IPv6 `::1` is the loopback address.
    def loopback? : Bool
      case addr = @addr
      in LibC::InAddr
        addr.s_addr & 0x000000ff_u32 == 0x0000007f_u32
      in LibC::In6Addr
        ipv6_addr8(addr) == StaticArray[0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 1_u8]
      end
    end

    # Returns `true` if this IP is an unspecified address, either the IPv4 address `0.0.0.0` or the IPv6 address `::`.
    def unspecified? : Bool
      case addr = @addr
      in LibC::InAddr
        addr.s_addr == 0_u32
      in LibC::In6Addr
        ipv6_addr8(addr) == StaticArray[0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8]
      end
    end

    # Returns `true` if this IP is a private address.
    #
    # IPv4 addresses in `10.0.0.0/8`, `172.16.0.0/12` and `192.168.0.0/16` as defined in [RFC 1918](https://tools.ietf.org/html/rfc1918)
    # and IPv6 Unique Local Addresses in `fc00::/7` as defined in [RFC 4193](https://tools.ietf.org/html/rfc4193) are considered private.
    def private? : Bool
      case addr = @addr
      in LibC::InAddr
        addr.s_addr & 0x000000ff_u32 == 0x00000000a_u32 ||     # 10.0.0.0/8
          addr.s_addr & 0x000000f0ff_u32 == 0x0000010ac_u32 || # 172.16.0.0/12
          addr.s_addr & 0x000000ffff_u32 == 0x0000a8c0_u32     # 192.168.0.0/16
      in LibC::In6Addr
        ipv6_addr8(addr)[0] & 0xfe_u8 == 0xfc_u8
      end
    end

    private def ipv6_addr8(addr : LibC::In6Addr)
      {% if flag?(:darwin) || flag?(:bsd) %}
        addr.__u6_addr.__u6_addr8
      {% elsif flag?(:linux) && flag?(:musl) %}
        addr.__in6_union.__s6_addr
      {% elsif flag?(:wasm32) %}
        addr.s6_addr
      {% elsif flag?(:linux) %}
        addr.__in6_u.__u6_addr8
      {% elsif flag?(:win32) %}
        addr.u.byte
      {% else %}
        {% raise "Unsupported platform" %}
      {% end %}
    end

    def_equals_and_hash family, port, address

    def to_s(io : IO) : Nil
      if family == Family::INET6
        io << '[' << address << ']' << ':' << port
      else
        io << address << ':' << port
      end
    end

    def inspect(io : IO) : Nil
      io << "Socket::IPAddress("
      to_s(io)
      io << ")"
    end

    def pretty_print(pp)
      pp.text inspect
    end

    def to_unsafe : LibC::Sockaddr*
      case addr = @addr
      in LibC::InAddr
        to_sockaddr_in(addr)
      in LibC::In6Addr
        to_sockaddr_in6(addr)
      end
    end

    private def to_sockaddr_in6(addr)
      sockaddr = Pointer(LibC::SockaddrIn6).malloc
      sockaddr.value.sin6_family = family
      {% if flag?(:dragonfly) %}
        sockaddr.value.sin6_port = Intrinsics.bswap16(port)
      {% else %}
        sockaddr.value.sin6_port = LibC.htons(port)
      {% end %}
      sockaddr.value.sin6_addr = addr
      sockaddr.as(LibC::Sockaddr*)
    end

    private def to_sockaddr_in(addr)
      sockaddr = Pointer(LibC::SockaddrIn).malloc
      sockaddr.value.sin_family = family
      {% if flag?(:dragonfly) %}
        sockaddr.value.sin_port = Intrinsics.bswap16(port)
      {% else %}
        sockaddr.value.sin_port = LibC.htons(port)
      {% end %}
      sockaddr.value.sin_addr = addr
      sockaddr.as(LibC::Sockaddr*)
    end

    # Returns `true` if *port* is a valid port number.
    #
    # Valid port numbers are in the range `0..65_535`.
    def self.valid_port?(port : Int) : Bool
      port.in?(0..UInt16::MAX)
    end
  end

  # UNIX address representation.
  #
  # Holds the local path of an UNIX address, usually coming from an opened
  # connection (e.g. `Socket#local_address`, `Socket#receive`).
  #
  # Example:
  # ```
  # require "socket"
  #
  # Socket::UNIXAddress.new("/tmp/my.sock")
  # ```
  struct UNIXAddress < Address
    getter path : String

    # :nodoc:
    MAX_PATH_SIZE = {% if flag?(:wasm32) %}
                      0
                    {% else %}
                      LibC::SockaddrUn.new.sun_path.size - 1
                    {% end %}

    def initialize(@path : String)
      if @path.bytesize + 1 > MAX_PATH_SIZE
        raise ArgumentError.new("Path size exceeds the maximum size of #{MAX_PATH_SIZE} bytes")
      end
      @family = Family::UNIX
      @size = {% if flag?(:wasm32) %}
                1
              {% else %}
                sizeof(LibC::SockaddrUn)
              {% end %}
    end

    # Creates an `UNIXSocket` from the internal OS representation.
    def self.from(sockaddr : LibC::Sockaddr*, addrlen) : UNIXAddress
      {% if flag?(:wasm32) %}
        raise NotImplementedError.new "Socket::UnixAddress.from"
      {% else %}
        new(sockaddr.as(LibC::SockaddrUn*), addrlen.to_i)
      {% end %}
    end

    # Parses a `Socket::UNIXAddress` from an URI.
    #
    # It expects the URI to include `<scheme>://<path>` where `scheme` as well
    # as any additional URI components (such as `fragment` or `query`) are ignored.
    #
    # If `host` is not empty, it will be prepended to `path` to form a relative
    # path.
    #
    # ```
    # require "socket"
    #
    # Socket::UNIXAddress.parse("unix:///foo.sock") # => Socket::UNIXAddress.new("/foo.sock")
    # Socket::UNIXAddress.parse("unix://foo.sock")  # => Socket::UNIXAddress.new("foo.sock")
    # ```
    def self.parse(uri : URI) : UNIXAddress
      unix_path = String.build do |io|
        io << uri.host
        if port = uri.port
          io << ':' << port
        end
        if path = uri.path.presence
          io << path
        end
      end

      raise Socket::Error.new("Invalid UNIX address: missing path") if unix_path.empty?

      {% if flag?(:unix) %}
        UNIXAddress.new(unix_path)
      {% else %}
        raise NotImplementedError.new("UNIX address not available")
      {% end %}
    end

    # :ditto:
    def self.parse(uri : String) : self
      parse URI.parse(uri)
    end

    {% unless flag?(:wasm32) %}
      protected def initialize(sockaddr : LibC::SockaddrUn*, size)
        @family = Family::UNIX
        @path = String.new(sockaddr.value.sun_path.to_unsafe)
        @size = size || sizeof(LibC::SockaddrUn)
      end
    {% end %}

    def_equals_and_hash path

    def to_s(io : IO) : Nil
      io << path
    end

    def to_unsafe : LibC::Sockaddr*
      {% if flag?(:wasm32) %}
        raise NotImplementedError.new "Socket::UnixAddress#to_unsafe"
      {% else %}
        sockaddr = Pointer(LibC::SockaddrUn).malloc
        sockaddr.value.sun_family = family
        sockaddr.value.sun_path.to_unsafe.copy_from(@path.to_unsafe, @path.bytesize + 1)
        sockaddr.as(LibC::Sockaddr*)
      {% end %}
    end
  end

  # Returns `true` if the string represents a valid IPv4 or IPv6 address.
  @[Deprecated("Use `IPAddress.valid?` instead")]
  def self.ip?(string : String)
    addr = LibC::In6Addr.new
    ptr = pointerof(addr).as(Void*)
    LibC.inet_pton(LibC::AF_INET, string, ptr) > 0 || LibC.inet_pton(LibC::AF_INET6, string, ptr) > 0
  end
end
