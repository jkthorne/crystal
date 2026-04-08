# ISO-2022-KR stateful codec
#
# Uses ESC $ ) C to designate KSC 5601 to G1, then SO/SI to shift.
#
# State machine modes (CodecState.mode):
#   0 = ASCII (SI state, initial)
#   1 = KSC 5601 invoked (SO state)
#
# CodecState.flags:
#   0 = not designated
#   1 = KSC 5601 designated

module CharConv::Codec::ISO2022KR
  def self.decode(src : Bytes, pos : Int32, state : Pointer(CodecState)) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1

    b0 = src.unsafe_fetch(pos)

    # ESC $ ) C — designate KSC 5601
    if b0 == 0x1B_u8
      return DecodeResult::TOOFEW if remaining < 4
      if src.unsafe_fetch(pos + 1) == 0x24_u8 &&
         src.unsafe_fetch(pos + 2) == 0x29_u8 &&
         src.unsafe_fetch(pos + 3) == 0x43_u8
        state.value.flags = 1_u8
        return DecodeResult.new(0_u32, 4)
      end
      return DecodeResult::ILSEQ
    end

    # SO — invoke G1 (KSC 5601)
    if b0 == 0x0E_u8
      return DecodeResult::ILSEQ if state.value.flags == 0_u8
      state.value.mode = 1_u8
      return DecodeResult.new(0_u32, 1)
    end

    # SI — return to ASCII
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

    # KSC 5601 mode
    return DecodeResult::TOOFEW if remaining < 2
    b1 = src.unsafe_fetch(pos + 1)
    return DecodeResult::ILSEQ unless b0 >= 0x21_u8 && b0 <= 0x7E_u8
    return DecodeResult::ILSEQ unless b1 >= 0x21_u8 && b1 <= 0x7E_u8

    # Convert to EUC-KR coordinates (add 0x80)
    lead = b0.to_i32 + 0x80
    trail = b1.to_i32 + 0x80
    idx = (lead - Tables::CJKKSC::EUCKR_LEAD_MIN) * Tables::CJKKSC::EUCKR_TRAIL_COUNT + (trail - Tables::CJKKSC::EUCKR_TRAIL_MIN)
    cp = Tables::CJKKSC::EUCKR_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode(cp : UInt32, dst : Bytes, pos : Int32, state : Pointer(CodecState)) : EncodeResult
    remaining = dst.size - pos

    # ASCII
    if cp < 0x80
      if state.value.mode != 0_u8
        return EncodeResult::TOOSMALL if remaining < 2
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

    # Try KSC 5601 encode via EUC-KR table
    high = (cp >> 8).to_i32 & 0xFF
    page_idx = Tables::CJKKSC::EUCKR_ENCODE_SUMMARY.unsafe_fetch(high)
    return EncodeResult::ILUNI if page_idx == 0xFFFF_u16

    encoded = Tables::CJKKSC::EUCKR_ENCODE_PAGES[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
    return EncodeResult::ILUNI if encoded == 0_u16

    kr_lead = ((encoded >> 8) - 0x80).to_u8
    kr_trail = ((encoded & 0xFF) - 0x80).to_u8
    return EncodeResult::ILUNI unless kr_lead >= 0x21 && kr_lead <= 0x7E
    return EncodeResult::ILUNI unless kr_trail >= 0x21 && kr_trail <= 0x7E

    needed = 2
    if state.value.flags != 1_u8
      needed += 4  # ESC $ ) C
    end
    if state.value.mode != 1_u8
      needed += 1  # SO
    end
    return EncodeResult::TOOSMALL if remaining < needed

    write_pos = pos
    if state.value.flags != 1_u8
      dst.to_unsafe[write_pos] = 0x1B_u8
      dst.to_unsafe[write_pos + 1] = 0x24_u8
      dst.to_unsafe[write_pos + 2] = 0x29_u8
      dst.to_unsafe[write_pos + 3] = 0x43_u8
      state.value.flags = 1_u8
      write_pos += 4
    end
    if state.value.mode != 1_u8
      dst.to_unsafe[write_pos] = 0x0E_u8  # SO
      state.value.mode = 1_u8
      write_pos += 1
    end
    dst.to_unsafe[write_pos] = kr_lead
    dst.to_unsafe[write_pos + 1] = kr_trail
    EncodeResult.new(write_pos + 2 - pos)
  end

  def self.flush(dst : Bytes, pos : Int32, state : Pointer(CodecState)) : Int32
    if state.value.mode != 0_u8
      remaining = dst.size - pos
      return 0 if remaining < 1
      dst.to_unsafe[pos] = 0x0F_u8
      state.value.mode = 0_u8
      return 1
    end
    0
  end
end
