{% if flag?(:use_libz) %}
  require "lib_z"
{% else %}
  require "z"
{% end %}

require "./digest"

# Implements the CRC32 checksum algorithm.
#
# NOTE: To use `CRC32`, you must explicitly import it with `require "digest/crc32"`
class Digest::CRC32 < ::Digest
  extend ClassMethods

  @digest : UInt32

  def initialize
    @digest = CRC32.initial
  end

  {% if flag?(:use_libz) %}

    def self.initial : UInt32
      LibZ.crc32(0, nil, 0).to_u32
    end

    def self.checksum(data) : UInt32
      update(data, initial)
    end

    def self.update(data, crc32 : UInt32) : UInt32
      update data.to_slice, crc32
    end

    def self.update(data : Bytes, crc32 : UInt32) : UInt32
      LibZ.crc32(crc32, data, data.size).to_u32
    end

    def self.combine(crc1 : UInt32, crc2 : UInt32, len : Int32) : UInt32
      LibZ.crc32_combine(crc1, crc2, len).to_u32
    end

  {% else %}

    def self.initial : UInt32
      0_u32
    end

    def self.checksum(data) : UInt32
      update(data, initial)
    end

    def self.update(data, crc32 : UInt32) : UInt32
      update data.to_slice, crc32
    end

    def self.update(data : Bytes, crc32 : UInt32) : UInt32
      # LibZ convention: external CRC is finalized (XORed).
      # Convert to Z::CRC32 internal format, update, convert back.
      internal = crc32 ^ 0xFFFFFFFF_u32
      Z::CRC32.finalize(Z::CRC32.update(data, internal))
    end

    def self.combine(crc1 : UInt32, crc2 : UInt32, len : Int32) : UInt32
      # CRC32 combine is not commonly used; provide a basic implementation.
      # This matches the GF(2) matrix-based combine from zlib.
      crc32_combine_impl(crc1, crc2, len.to_i64)
    end

    private def self.crc32_combine_impl(crc1 : UInt32, crc2 : UInt32, len2 : Int64) : UInt32
      return crc1 if len2 == 0

      # Use the square-and-multiply approach for GF(2) matrix operations
      odd = uninitialized UInt32[32]
      even = uninitialized UInt32[32]

      # Put operator for one zero bit in odd
      odd[0] = 0xEDB88320_u32 # CRC-32 polynomial
      row = 1_u32
      31.times do |n|
        odd[n + 1] = row
        row <<= 1
      end

      # Put operator for two zero bits in even
      gf2_matrix_square(even.to_slice, odd.to_slice)
      # Put operator for four zero bits in odd
      gf2_matrix_square(odd.to_slice, even.to_slice)

      crc1 ^= 0xFFFFFFFF_u32
      remaining = len2
      loop do
        # Apply zeros operator for this bit of len2
        if remaining & 1 != 0
          crc1 = gf2_matrix_times(odd.to_slice, crc1)
        end
        remaining >>= 1
        break if remaining == 0

        # Another iteration of the loop with odd and even swapped
        gf2_matrix_square(even.to_slice, odd.to_slice)
        if remaining & 1 != 0
          crc1 = gf2_matrix_times(even.to_slice, crc1)
        end
        remaining >>= 1
        break if remaining == 0

        gf2_matrix_square(odd.to_slice, even.to_slice)
      end

      crc1 ^= 0xFFFFFFFF_u32
      crc1 ^ crc2
    end

    private def self.gf2_matrix_times(mat : Bytes | Slice(UInt32), vec : UInt32) : UInt32
      sum = 0_u32
      i = 0
      v = vec
      while v != 0
        if v & 1 != 0
          sum ^= mat[i]
        end
        v >>= 1
        i += 1
      end
      sum
    end

    private def self.gf2_matrix_square(square : Bytes | Slice(UInt32), mat : Bytes | Slice(UInt32)) : Nil
      32.times do |n|
        square[n] = gf2_matrix_times(mat, mat[n])
      end
    end

  {% end %}

  # :nodoc:
  def update_impl(data : Bytes) : Nil
    @digest = CRC32.update(data, @digest)
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
    @digest = CRC32.initial
  end

  # :nodoc:
  def digest_size : Int32
    4
  end
end
