module Z
  module Adler32
    MODULO = 65521_u32
    NMAX   =  5552

    def self.initial : UInt32
      1_u32
    end

    def self.checksum(data : Bytes) : UInt32
      update(data, initial)
    end

    def self.checksum(str : String) : UInt32
      checksum(str.to_slice)
    end

    # SIMD weight vector for the b accumulation: lane i contributes weight (BLOCK - i).
    # data[0]*16 + data[1]*15 + ... + data[15]*1
    SIMD_BLOCK = 16

    # Maximum number of 16-byte blocks before UInt16 accumulator overflows.
    # Each lane accumulates at most MAX_BLOCK_ITERS * 255 = 65,280 <= 65,535.
    MAX_BLOCK_ITERS = 256

    def self.update(data : Bytes, adler : UInt32) : UInt32
      a = adler & 0xFFFF_u32
      b = (adler >> 16) & 0xFFFF_u32

      offset = 0
      remaining = data.size

      # Weight vector for b accumulation: lane i contributes weight (16 - i).
      # data[0]*16 + data[1]*15 + ... + data[15]*1
      weights = SIMDVector[16_u16, 15_u16, 14_u16, 13_u16,
                           12_u16, 11_u16, 10_u16, 9_u16,
                           8_u16, 7_u16, 6_u16, 5_u16,
                           4_u16, 3_u16, 2_u16, 1_u16]

      while remaining > 0
        # Work in NMAX-sized chunks to limit modular reduction frequency.
        # Round down to SIMD_BLOCK boundary.
        chunk = {remaining, NMAX - (NMAX % SIMD_BLOCK)}.min
        remaining -= chunk
        blocks = chunk // SIMD_BLOCK
        tail = chunk - blocks * SIMD_BLOCK

        # Process SIMD_BLOCK (16) bytes at a time using SIMD.
        # Sub-chunk every MAX_BLOCK_ITERS to prevent UInt16 overflow.
        while blocks > 0
          sub = {blocks, MAX_BLOCK_ITERS}.min
          blocks -= sub

          va = SIMDVector(UInt16, 16).zero # partial byte sums per lane
          vb = 0_u32                       # weighted sum accumulator

          sub.times do
            raw = SIMDVector(UInt8, 16).unsafe_load(data.to_unsafe + offset)
            wide = raw.widen(UInt16)

            # b accumulates a * BLOCK before new bytes are added to a
            b &+= a &* SIMD_BLOCK.to_u32

            va = va + wide

            # Weighted contribution to b: data[0]*16 + data[1]*15 + ...
            vb &+= (wide * weights).reduce_add.to_u32

            offset += SIMD_BLOCK
          end

          a &+= va.reduce_add.to_u32
          b &+= vb
        end

        # Process remaining bytes (scalar tail)
        tail.times do
          a &+= data[offset]
          b &+= a
          offset += 1
        end

        a %= MODULO
        b %= MODULO
      end

      (b << 16) | a
    end
  end
end
