{% if flag?(:use_libz) %}
  require "lib_z"
{% else %}
  require "z"
{% end %}

require "./digest"

# Implements the Adler32 checksum algorithm.
#
# NOTE: To use `Adler32`, you must explicitly import it with `require "digest/adler32"`
class Digest::Adler32 < ::Digest
  extend ClassMethods

  @digest : UInt32

  def initialize
    @digest = Adler32.initial
  end

  {% if flag?(:use_libz) %}

    def self.initial : UInt32
      LibZ.adler32(0, nil, 0).to_u32
    end

    def self.checksum(data) : UInt32
      update(data, initial)
    end

    def self.update(data, adler32 : UInt32) : UInt32
      update data.to_slice, adler32
    end

    def self.update(data : Bytes, adler32 : UInt32) : UInt32
      LibZ.adler32(adler32, data, data.size).to_u32
    end

    def self.combine(adler1 : UInt32, adler2 : UInt32, len : Int32) : UInt32
      LibZ.adler32_combine(adler1, adler2, len).to_u32
    end

  {% else %}

    def self.initial : UInt32
      Z::Adler32.initial
    end

    def self.checksum(data) : UInt32
      update(data, initial)
    end

    def self.update(data, adler32 : UInt32) : UInt32
      update data.to_slice, adler32
    end

    def self.update(data : Bytes, adler32 : UInt32) : UInt32
      Z::Adler32.update(data, adler32)
    end

    def self.combine(adler1 : UInt32, adler2 : UInt32, len : Int32) : UInt32
      # Adler32 combine: merge two checksums
      mod = 65521_u32
      a1 = adler1 & 0xFFFF_u32
      b1 = (adler1 >> 16) & 0xFFFF_u32
      a2 = adler2 & 0xFFFF_u32
      b2 = (adler2 >> 16) & 0xFFFF_u32

      rem = len.to_u64 % mod
      a = (a1 + a2 + mod - 1) % mod
      b = (b1 + b2 + rem * a1 + mod - rem) % mod
      (b << 16) | a
    end

  {% end %}

  # :nodoc:
  def update_impl(data : Bytes) : Nil
    @digest = Adler32.update(data, @digest)
  end

  # :nodoc:
  def final_impl(dst : Bytes) : Nil
    dst[0] = (@digest >> 24).to_u8!
    dst[1] = (@digest >> 16).to_u8!
    dst[2] = (@digest >> 8).to_u8!
    dst[3] = (@digest).to_u8!
  end

  # :nodoc:
  def reset_impl : Nil
    @digest = Adler32.initial
  end

  # :nodoc:
  def digest_size : Int32
    4
  end
end
