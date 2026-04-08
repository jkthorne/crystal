# GB18030 codec
#
# GB18030 has three forms:
#   1-byte: 0x00-0x7F (ASCII)
#   2-byte: lead 0x81-0xFE, trail 0x40-0x7E or 0x80-0xFE (GBK compatible)
#   4-byte: byte1(0x81-0xFE) byte2(0x30-0x39) byte3(0x81-0xFE) byte4(0x30-0x39)
#
# The 4-byte form covers all of Unicode not covered by 2-byte form.
# Linear index: ((b1-0x81)*10 + (b2-0x30)) * 126 * 10 + (b3-0x81) * 10 + (b4-0x30)

module CharConv::Codec::GB18030
  # Decode GB18030
  def self.decode(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    # 1-byte: ASCII
    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    return DecodeResult::ILSEQ unless b0 >= 0x81 && b0 <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    b1 = src.unsafe_fetch(pos + 1)

    # 4-byte form: byte2 is 0x30-0x39
    if b1 >= 0x30_u8 && b1 <= 0x39_u8
      return DecodeResult::TOOFEW if remaining < 4
      b2 = src.unsafe_fetch(pos + 2)
      b3 = src.unsafe_fetch(pos + 3)
      return DecodeResult::ILSEQ unless b2 >= 0x81 && b2 <= 0xFE
      return DecodeResult::ILSEQ unless b3 >= 0x30 && b3 <= 0x39

      linear = ((b0.to_i32 - 0x81) * 10 + (b1.to_i32 - 0x30)) * 126 * 10 +
               (b2.to_i32 - 0x81) * 10 + (b3.to_i32 - 0x30)

      cp = linear_to_unicode(linear)
      return cp == 0xFFFFFFFF_u32 ? DecodeResult::ILSEQ : DecodeResult.new(cp, 4)
    end

    # 2-byte form (GBK compatible)
    return DecodeResult::ILSEQ unless (b1 >= 0x40 && b1 <= 0x7E) || (b1 >= 0x80 && b1 <= 0xFE)

    idx = (b0.to_i32 - Tables::CJKGB::GBK_LEAD_MIN) * Tables::CJKGB::GBK_TRAIL_COUNT + (b1.to_i32 - Tables::CJKGB::GBK_TRAIL_MIN)
    cp = Tables::CJKGB::GBK_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  # Encode GB18030
  def self.encode(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    # ASCII
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    # Try 2-byte GBK encode first (BMP only)
    if cp <= 0xFFFF
      high = (cp >> 8).to_i32 & 0xFF
      page_idx = Tables::CJKGB::GBK_ENCODE_SUMMARY.unsafe_fetch(high)
      if page_idx != 0xFFFF_u16
        encoded = Tables::CJKGB::GBK_ENCODE_PAGES[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
        if encoded != 0_u16
          return EncodeResult::TOOSMALL if dst.size - pos < 2
          dst.to_unsafe[pos] = (encoded >> 8).to_u8
          dst.to_unsafe[pos + 1] = (encoded & 0xFF).to_u8
          return EncodeResult.new(2)
        end
      end
    end

    # 4-byte form
    return EncodeResult::TOOSMALL if dst.size - pos < 4
    linear = unicode_to_linear(cp)
    return EncodeResult::ILUNI if linear < 0

    b4 = (linear % 10 + 0x30).to_u8
    linear //= 10
    b3 = (linear % 126 + 0x81).to_u8
    linear //= 126
    b2 = (linear % 10 + 0x30).to_u8
    linear //= 10
    b1 = (linear + 0x81).to_u8

    return EncodeResult::ILUNI if b1 > 0xFE

    dst.to_unsafe[pos] = b1
    dst.to_unsafe[pos + 1] = b2
    dst.to_unsafe[pos + 2] = b3
    dst.to_unsafe[pos + 3] = b4
    EncodeResult.new(4)
  end

  # Convert GB18030 4-byte linear index to Unicode codepoint
  @[AlwaysInline]
  private def self.linear_to_unicode(linear : Int32) : UInt32
    # Supplementary plane: simple offset from linear 189000
    supp_start = Tables::GB18030Ranges::SUPP_START_LINEAR
    if linear >= supp_start
      cp = (linear - supp_start + 0x10000).to_u32
      return cp <= 0x10FFFF ? cp : 0xFFFFFFFF_u32
    end

    # BMP: binary search through range table
    ranges = Tables::GB18030Ranges::BMP_RANGES
    lo = 0
    hi = ranges.size - 1
    while lo <= hi
      mid = (lo + hi) >> 1
      range_linear_start, range_unicode_start, range_count = ranges[mid]
      if linear < range_linear_start
        hi = mid - 1
      elsif linear >= range_linear_start + range_count
        lo = mid + 1
      else
        return (range_unicode_start + (linear - range_linear_start)).to_u32
      end
    end

    0xFFFFFFFF_u32
  end

  # Convert Unicode codepoint to GB18030 4-byte linear index
  @[AlwaysInline]
  private def self.unicode_to_linear(cp : UInt32) : Int32
    # Supplementary plane
    if cp >= 0x10000
      return cp.to_i32 - 0x10000 + Tables::GB18030Ranges::SUPP_START_LINEAR
    end

    # BMP: binary search by unicode_start
    ranges = Tables::GB18030Ranges::BMP_RANGES
    lo = 0
    hi = ranges.size - 1
    while lo <= hi
      mid = (lo + hi) >> 1
      range_linear_start, range_unicode_start, range_count = ranges[mid]
      ustart = range_unicode_start.to_u32
      if cp < ustart
        hi = mid - 1
      elsif cp >= ustart + range_count
        lo = mid + 1
      else
        return range_linear_start + (cp - ustart).to_i32
      end
    end

    -1
  end
end
