# ISO-2022-CN stateful codec
#
# State machine modes (CodecState.mode):
#   0 = ASCII (initial, SI state)
#   1 = GB2312 designated and invoked (SO with G1=GB2312)
#   2 = CNS 11643 plane 1 designated and invoked (SO with G1=CNS)
#
# CodecState.flags tracks G1 designation:
#   0 = nothing designated
#   1 = GB2312 designated (ESC $ ) A)
#   2 = CNS 11643 plane 1 designated (ESC $ ) G)
#
# Shift: SO (0x0E) invokes G1, SI (0x0F) returns to ASCII

module CharConv::Codec::ISO2022CN
  def self.decode(src : Bytes, pos : Int32, state : Pointer(CodecState)) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1

    b0 = src.unsafe_fetch(pos)

    # ESC sequences
    if b0 == 0x1B_u8
      return DecodeResult::TOOFEW if remaining < 4
      b1 = src.unsafe_fetch(pos + 1)
      b2 = src.unsafe_fetch(pos + 2)
      b3 = src.unsafe_fetch(pos + 3)

      # ESC $ ) A — designate GB2312 to G1
      if b1 == 0x24_u8 && b2 == 0x29_u8 && b3 == 0x41_u8
        state.value.flags = 1_u8
        return DecodeResult.new(0_u32, 4)
      end

      # ESC $ ) G — designate CNS 11643 plane 1 to G1
      if b1 == 0x24_u8 && b2 == 0x29_u8 && b3 == 0x47_u8
        state.value.flags = 2_u8
        return DecodeResult.new(0_u32, 4)
      end

      return DecodeResult::ILSEQ
    end

    # SO (0x0E) — invoke G1
    if b0 == 0x0E_u8
      if state.value.flags == 1_u8
        state.value.mode = 1_u8
      elsif state.value.flags == 2_u8
        state.value.mode = 2_u8
      else
        return DecodeResult::ILSEQ  # no G1 designated
      end
      return DecodeResult.new(0_u32, 1)
    end

    # SI (0x0F) — return to ASCII
    if b0 == 0x0F_u8
      state.value.mode = 0_u8
      return DecodeResult.new(0_u32, 1)
    end

    mode = state.value.mode

    # ASCII mode
    if mode == 0_u8
      return DecodeResult::ILSEQ if b0 >= 0x80
      return DecodeResult.new(b0.to_u32, 1)
    end

    # GB2312 or CNS mode: two 7-bit bytes
    return DecodeResult::TOOFEW if remaining < 2
    b1 = src.unsafe_fetch(pos + 1)
    return DecodeResult::ILSEQ unless b0 >= 0x21_u8 && b0 <= 0x7E_u8
    return DecodeResult::ILSEQ unless b1 >= 0x21_u8 && b1 <= 0x7E_u8

    if mode == 1_u8
      # GB2312: convert to EUC-CN coordinates
      lead = b0.to_i32 + 0x80
      trail = b1.to_i32 + 0x80
      return DecodeResult::ILSEQ unless lead >= Tables::CJKGB::EUCCN_LEAD_MIN && lead <= Tables::CJKGB::EUCCN_LEAD_MAX
      idx = (lead - Tables::CJKGB::EUCCN_LEAD_MIN) * Tables::CJKGB::EUCCN_TRAIL_COUNT + (trail - Tables::CJKGB::EUCCN_TRAIL_MIN)
      cp = Tables::CJKGB::EUCCN_DECODE.unsafe_fetch(idx)
      return cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
    end

    if mode == 2_u8
      # CNS 11643 plane 1: convert to EUC-TW coordinates
      lead = b0.to_i32 + 0x80
      trail = b1.to_i32 + 0x80
      return DecodeResult::ILSEQ unless lead >= Tables::CJKEUCTW::EUCTW_LEAD_MIN && lead <= Tables::CJKEUCTW::EUCTW_LEAD_MAX
      idx = (lead - Tables::CJKEUCTW::EUCTW_LEAD_MIN) * Tables::CJKEUCTW::EUCTW_TRAIL_COUNT + (trail - Tables::CJKEUCTW::EUCTW_TRAIL_MIN)
      cp = Tables::CJKEUCTW::EUCTW_DECODE.unsafe_fetch(idx)
      return cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
    end

    DecodeResult::ILSEQ
  end

  def self.encode(cp : UInt32, dst : Bytes, pos : Int32, state : Pointer(CodecState)) : EncodeResult
    remaining = dst.size - pos

    # ASCII range
    if cp < 0x80
      if state.value.mode != 0_u8
        return EncodeResult::TOOSMALL if remaining < 2  # SI + char
        dst.to_unsafe[pos] = 0x0F_u8  # SI
        state.value.mode = 0_u8
        dst.to_unsafe[pos + 1] = cp.to_u8
        return EncodeResult.new(2)
      end
      return EncodeResult::TOOSMALL if remaining < 1
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::ILUNI if cp > 0xFFFF

    # Try GB2312 encode
    high = (cp >> 8).to_i32 & 0xFF
    page_idx = Tables::CJKGB::EUCCN_ENCODE_SUMMARY.unsafe_fetch(high)
    if page_idx != 0xFFFF_u16
      encoded = Tables::CJKGB::EUCCN_ENCODE_PAGES[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
      if encoded != 0_u16
        gb_lead = ((encoded >> 8) - 0x80).to_u8
        gb_trail = ((encoded & 0xFF) - 0x80).to_u8

        if gb_lead >= 0x21 && gb_lead <= 0x7E && gb_trail >= 0x21 && gb_trail <= 0x7E
          needed = 2
          # Need designation?
          if state.value.flags != 1_u8
            needed += 4  # ESC $ ) A
          end
          # Need SO?
          if state.value.mode != 1_u8
            needed += 1  # SO
          end
          return EncodeResult::TOOSMALL if remaining < needed

          write_pos = pos
          if state.value.flags != 1_u8
            dst.to_unsafe[write_pos] = 0x1B_u8
            dst.to_unsafe[write_pos + 1] = 0x24_u8
            dst.to_unsafe[write_pos + 2] = 0x29_u8
            dst.to_unsafe[write_pos + 3] = 0x41_u8
            state.value.flags = 1_u8
            write_pos += 4
          end
          if state.value.mode != 1_u8
            dst.to_unsafe[write_pos] = 0x0E_u8  # SO
            state.value.mode = 1_u8
            write_pos += 1
          end
          dst.to_unsafe[write_pos] = gb_lead
          dst.to_unsafe[write_pos + 1] = gb_trail
          return EncodeResult.new(write_pos + 2 - pos)
        end
      end
    end

    EncodeResult::ILUNI
  end

  def self.flush(dst : Bytes, pos : Int32, state : Pointer(CodecState)) : Int32
    if state.value.mode != 0_u8
      remaining = dst.size - pos
      return 0 if remaining < 1
      dst.to_unsafe[pos] = 0x0F_u8  # SI
      state.value.mode = 0_u8
      return 1
    end
    0
  end
end
