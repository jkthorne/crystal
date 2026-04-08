# HZ (HZ-GB-2312) stateful codec
#
# Encoding framing:
#   ~{ — switch to GB2312 mode (2-byte characters, row/cell 0x21-0x7E)
#   ~} — switch to ASCII mode
#   ~~ — literal tilde in ASCII mode
#   ~\n — ignored (line continuation)
#
# State (CodecState.mode):
#   0 = ASCII mode (initial)
#   1 = GB2312 mode

module CharConv::Codec::HZ
  def self.decode(src : Bytes, pos : Int32, state : Pointer(CodecState)) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1

    b0 = src.unsafe_fetch(pos)
    mode = state.value.mode

    # Handle tilde escapes
    if b0 == 0x7E_u8  # ~
      return DecodeResult::TOOFEW if remaining < 2
      b1 = src.unsafe_fetch(pos + 1)

      # ~{ — enter GB2312 mode
      if b1 == 0x7B_u8
        state.value.mode = 1_u8
        return DecodeResult.new(0_u32, 2)  # mode switch, no character
      end

      # ~} — enter ASCII mode
      if b1 == 0x7D_u8
        state.value.mode = 0_u8
        return DecodeResult.new(0_u32, 2)
      end

      # ~~ — literal tilde
      if b1 == 0x7E_u8
        return DecodeResult.new(0x7E_u32, 2)
      end

      # ~\n — line continuation (skip)
      if b1 == 0x0A_u8
        return DecodeResult.new(0_u32, 2)
      end

      return DecodeResult::ILSEQ
    end

    # ASCII mode
    if mode == 0_u8
      return DecodeResult::ILSEQ if b0 >= 0x80
      return DecodeResult.new(b0.to_u32, 1)
    end

    # GB2312 mode: two bytes, both 0x21-0x7E
    return DecodeResult::TOOFEW if remaining < 2
    b1 = src.unsafe_fetch(pos + 1)
    return DecodeResult::ILSEQ unless b0 >= 0x21_u8 && b0 <= 0x7E_u8
    return DecodeResult::ILSEQ unless b1 >= 0x21_u8 && b1 <= 0x7E_u8

    # Convert to EUC-CN coordinates (add 0x80)
    lead = b0.to_i32 + 0x80
    trail = b1.to_i32 + 0x80

    return DecodeResult::ILSEQ unless lead >= Tables::CJKGB::EUCCN_LEAD_MIN && lead <= Tables::CJKGB::EUCCN_LEAD_MAX
    return DecodeResult::ILSEQ unless trail >= Tables::CJKGB::EUCCN_TRAIL_MIN && trail <= Tables::CJKGB::EUCCN_TRAIL_MAX

    idx = (lead - Tables::CJKGB::EUCCN_LEAD_MIN) * Tables::CJKGB::EUCCN_TRAIL_COUNT + (trail - Tables::CJKGB::EUCCN_TRAIL_MIN)
    cp = Tables::CJKGB::EUCCN_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode(cp : UInt32, dst : Bytes, pos : Int32, state : Pointer(CodecState)) : EncodeResult
    remaining = dst.size - pos

    # Tilde needs escaping in ASCII mode
    if cp == 0x7E_u32
      if state.value.mode != 0_u8
        # Switch to ASCII first
        return EncodeResult::TOOSMALL if remaining < 4  # ~} + ~~
        dst.to_unsafe[pos] = 0x7E_u8
        dst.to_unsafe[pos + 1] = 0x7D_u8
        dst.to_unsafe[pos + 2] = 0x7E_u8
        dst.to_unsafe[pos + 3] = 0x7E_u8
        state.value.mode = 0_u8
        return EncodeResult.new(4)
      end
      return EncodeResult::TOOSMALL if remaining < 2
      dst.to_unsafe[pos] = 0x7E_u8
      dst.to_unsafe[pos + 1] = 0x7E_u8
      return EncodeResult.new(2)
    end

    # ASCII range
    if cp < 0x80
      if state.value.mode != 0_u8
        return EncodeResult::TOOSMALL if remaining < 3  # ~} + char
        dst.to_unsafe[pos] = 0x7E_u8
        dst.to_unsafe[pos + 1] = 0x7D_u8
        state.value.mode = 0_u8
        dst.to_unsafe[pos + 2] = cp.to_u8
        return EncodeResult.new(3)
      end
      return EncodeResult::TOOSMALL if remaining < 1
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    # Try GB2312 encode via EUC-CN table
    return EncodeResult::ILUNI if cp > 0xFFFF

    high = (cp >> 8).to_i32 & 0xFF
    page_idx = Tables::CJKGB::EUCCN_ENCODE_SUMMARY.unsafe_fetch(high)
    return EncodeResult::ILUNI if page_idx == 0xFFFF_u16

    encoded = Tables::CJKGB::EUCCN_ENCODE_PAGES[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
    return EncodeResult::ILUNI if encoded == 0_u16

    # Convert from EUC-CN to GB2312 7-bit (subtract 0x80)
    gb_lead = ((encoded >> 8) - 0x80).to_u8
    gb_trail = ((encoded & 0xFF) - 0x80).to_u8

    return EncodeResult::ILUNI unless gb_lead >= 0x21 && gb_lead <= 0x7E
    return EncodeResult::ILUNI unless gb_trail >= 0x21 && gb_trail <= 0x7E

    if state.value.mode != 1_u8
      return EncodeResult::TOOSMALL if remaining < 4  # ~{ + 2 chars
      dst.to_unsafe[pos] = 0x7E_u8
      dst.to_unsafe[pos + 1] = 0x7B_u8
      state.value.mode = 1_u8
      dst.to_unsafe[pos + 2] = gb_lead
      dst.to_unsafe[pos + 3] = gb_trail
      return EncodeResult.new(4)
    end

    return EncodeResult::TOOSMALL if remaining < 2
    dst.to_unsafe[pos] = gb_lead
    dst.to_unsafe[pos + 1] = gb_trail
    EncodeResult.new(2)
  end

  # Flush: return to ASCII mode at end of output
  def self.flush(dst : Bytes, pos : Int32, state : Pointer(CodecState)) : Int32
    if state.value.mode != 0_u8
      remaining = dst.size - pos
      return 0 if remaining < 2
      dst.to_unsafe[pos] = 0x7E_u8
      dst.to_unsafe[pos + 1] = 0x7D_u8
      state.value.mode = 0_u8
      return 2
    end
    0
  end
end
