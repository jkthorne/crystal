require "secure_random"

# Universally Unique IDentifier.
#
# Supports [RFC4122](https://www.ietf.org/rfc/rfc4122.txt) UUIDs and custom
# variants with arbitrary 16 bytes.
struct UUID
  enum Variant
    # Unknown (ie. custom, your own).
    Unknown

    # Reserved by the NCS for backward compatibility.
    NCS

    # As described in the RFC4122 Specification (default).
    RFC4122

    # Reserved by Microsoft for backward compatibility.
    Microsoft

    # Reserved for future expansion.
    Future
  end

  # RFC4122 UUID variant versions.
  enum Version
    # Unknown version.
    Unknown = 0

    # Version 1 - date-time and MAC address.
    V1 = 1

    # Version 2 - DCE security.
    V2 = 2

    # Version 3 - MD5 hash and namespace.
    V3 = 3

    # Version 4 - random.
    V4 = 4

    # Version 5 - SHA1 hash and namespace.
    V5 = 5
  end


  # Internal representation.
  @bytes : StaticArray(UInt8, 16)

  # Generates nil UUID, filled with zero bytes.
  def self.empty
    new StaticArray(UInt8, 16).new(0_u8)
  end

  # Generates RFC4122 v4 UUID using a secure random source.
  def self.random
    bytes = uninitialized UInt8[16]
    SecureRandom.random_bytes(bytes.to_slice)
    new(bytes, Variant::RFC4122, Version::V4)
  end

  # Decodes UUID from string *value*.
  #
  # Supports hyphenated (e.g. `ba714f86-cac6-42c7-8956-bcf5105e1b81`),
  # hexstring (e.g. `89370a4ab66440c8add39e06f2bb6af6`) or URN (e.g.
  # `urn:uuid:3f9eaf9e-cdb0-45cc-8ecb-0e5b2bfb0c20`) formats.
  def initialize(value : String)
    @bytes = uninitialized UInt8[16]
    decode(value)
  end

  # Creates UUID from 16-bytes slice.
  def initialize(slice : Slice(UInt8))
    raise ArgumentError.new "Invalid bytes length #{@bytes.size}, expected 16." unless slice.size == 16
    @bytes = uninitialized UInt8[16]
    @bytes.to_unsafe.copy_from(slice)
  end

  # Creates UUID from 16-bytes static array.
  def initialize(@bytes)
  end

  # Creates UUID from bytes, applying *version* and *variant* to the UUID.
  def initialize(@bytes, variant : Variant, version : Version)
    self.variant = variant
    self.version = version
  end

  delegate to_slice, to: @bytes
  delegate to_unsafe, to: @bytes

  def variant
    case
    when @bytes[8] & 0x80 == 0x00
      Variant::NCS
    when @bytes[8] & 0xc0 == 0x80
      Variant::RFC4122
    when @bytes[8] & 0xe0 == 0xc0
      Variant::Microsoft
    when @bytes[8] & 0xe0 == 0xe0
      Variant::Future
    else
      Variant::Unknown
    end
  end

  def variant=(value : Variant)
    case value
    when Variant::NCS
      @bytes[8] = (@bytes[8] & 0x7f)
    when Variant::RFC4122
      @bytes[8] = (@bytes[8] & 0x3f) | 0x80
    when Variant::Microsoft
      @bytes[8] = (@bytes[8] & 0x1f) | 0xc0
    when Variant::Future
      @bytes[8] = (@bytes[8] & 0x1f) | 0xe0
    else
      raise ArgumentError.new "Can't set unknown variant."
    end
  end

  # Returns version based on RFC4122 format. See also `#variant`.
  def version
    case @bytes[6] >> 4
    when 1 then Version::V1
    when 2 then Version::V2
    when 3 then Version::V3
    when 4 then Version::V4
    when 5 then Version::V5
    else        Version::Unknown
    end
  end

  # Sets `version`. Doesn't set variant (see `#variant=`).
  def version=(value : Version)
    raise ArgumentError.new "Can't set unknown version." if value.unknown?
    @bytes[6] = (@bytes[6] & 0xf) | (value.to_u8 << 4)
  end

  {% for v in %w(1 2 3 4 5) %}
    # Returns true if UUID is a `Version::V{{ v.id }}`, false otherwise.
    def v{{ v.id }}?
      variant == Variant::RFC4122 && version == Version::V{{ v.id }}
    end

    # Raises `Error` unless UUID is a `Version::V{{ v.id }}`.
    def v{{ v.id }}!
      unless v{{ v.id }}?
        raise Error.new("Invalid UUID variant #{variant} version #{version}, expected RFC4122 V{{ v.id }}.")
      end
    end
  {% end %}

  def ==(other : String)
    self == UUID.new(other)
  end

  def ==(other : Slice(UInt8))
    to_slice == other
  end

  def ==(other : StaticArray(UInt8, 16))
    @bytes == other
  end

  protected def decode(value : String)
    case value.size
    when 36 # hyphenated
      8.step(to: 23, by: 5) do |offset|
        raise ArgumentError.new "Invalid UUID string format, expected hyphen at char #{offset}." unless value[offset] == '-'
      end
      {0, 2, 4, 6, 9, 11, 14, 16, 19, 21, 24, 26, 28, 30, 32, 34}.each_with_index do |offset, i|
        @bytes[i] = value[offset, 2].to_u8(16, whitespace: false, underscore: false, prefix: false)
      end
    when 32 # hexstring
      16.times do |i|
        @bytes[i] = value[i * 2, 2].to_u8(16, whitespace: false, underscore: false, prefix: false)
      end
    when 45 # URN
      raise ArgumentError.new "Invalid URN UUID format, expected string starting with \":urn:uuid:\"." unless value.starts_with?("urn:uuid:")
      {9, 11, 13, 15, 18, 20, 23, 25, 28, 30, 33, 35, 37, 39, 41, 43}.each_with_index do |offset, i|
        @bytes[i] = value[offset, 2].to_u8(16, whitespace: false, underscore: false, prefix: false)
      end
    else
      raise ArgumentError.new "Invalid string length #{value.size} for UUID, expected 32 (hexstring), 36 (hyphenated) or 46 (urn)."
    end
  end

  # Writes hyphenated representation of UUID to *io*.
  def to_s(io : IO)
    @bytes.each_with_index do |byte, i|
      io << '0' if byte < 16
      byte.to_s(16, io)
      io << '-' if i == 3 || i == 5 || i == 7 || i == 9
    end
  end

  def to_s
    String.new(36) do |buffer|
      format_hyphenated(buffer)
      {36, 36}
    end
  end

  def hexstring
    to_slice.hexstring
  end

  def urn
    String.new(45) do |buffer|
      buffer.copy_from("urn:uuid:".to_unsafe, 9)
      format_hyphenated(buffer + 9)
      {45, 45}
    end
  end

  protected def format_hyphenated(buffer)
    buffer[8] = buffer[13] = buffer[18] = buffer[23] = 45_u8
    to_slice[0, 4].hexstring(buffer + 0)
    to_slice[4, 2].hexstring(buffer + 9)
    to_slice[6, 2].hexstring(buffer + 14)
    to_slice[8, 2].hexstring(buffer + 19)
    to_slice[10, 6].hexstring(buffer + 24)
  end
end
