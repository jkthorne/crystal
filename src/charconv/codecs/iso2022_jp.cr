# ISO-2022-JP stateful codec
#
# State machine modes (stored in CodecState.mode):
#   0 = ASCII (ESC ( B)
#   1 = JIS X 0201 Roman (ESC ( J) — same as ASCII except 0x5C=¥, 0x7E=‾
#   2 = JIS X 0208-1978 (ESC $ @)
#   3 = JIS X 0208-1983 (ESC $ B)
#
# ISO-2022-JP-1 adds:
#   4 = JIS X 0212-1990 (ESC $ ( D)
#
# ISO-2022-JP-2 adds:
#   5 = GB2312 (ESC $ A)
#   6 = KSC5601 (ESC $ ( C)
#   7 = ISO-8859-1 (ESC . A — G1 designation)
#   8 = ISO-8859-7 (ESC . F — G1 designation)
#
# For now we implement base ISO-2022-JP (modes 0-3).

module CharConv::Codec::ISO2022JP
  # Decode: reads escape sequences to switch modes, then decodes characters
  def self.decode(src : Bytes, pos : Int32, state : Pointer(CodecState)) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1

    b0 = src.unsafe_fetch(pos)

    # Handle escape sequences
    if b0 == 0x1B_u8  # ESC
      return DecodeResult::TOOFEW if remaining < 3

      b1 = src.unsafe_fetch(pos + 1)
      b2 = src.unsafe_fetch(pos + 2)

      # ESC ( B — ASCII
      if b1 == 0x28_u8 && b2 == 0x42_u8
        state.value.mode = 0_u8
        return DecodeResult.new(0_u32, 3)  # consumed 3 bytes, no character output
      end

      # ESC ( J — JIS X 0201 Roman
      if b1 == 0x28_u8 && b2 == 0x4A_u8
        state.value.mode = 1_u8
        return DecodeResult.new(0_u32, 3)
      end

      # ESC $ @ — JIS X 0208-1978
      if b1 == 0x24_u8 && b2 == 0x40_u8
        state.value.mode = 2_u8
        return DecodeResult.new(0_u32, 3)
      end

      # ESC $ B — JIS X 0208-1983
      if b1 == 0x24_u8 && b2 == 0x42_u8
        state.value.mode = 3_u8
        return DecodeResult.new(0_u32, 3)
      end

      # ESC $ ( D — JIS X 0212-1990 (ISO-2022-JP-1)
      if remaining >= 4 && b1 == 0x24_u8 && b2 == 0x28_u8 && src.unsafe_fetch(pos + 3) == 0x44_u8
        state.value.mode = 4_u8
        return DecodeResult.new(0_u32, 4)
      end

      return DecodeResult::ILSEQ
    end

    mode = state.value.mode

    # ASCII mode or JIS X 0201 Roman mode
    if mode == 0_u8 || mode == 1_u8
      return DecodeResult::ILSEQ if b0 >= 0x80  # no high bytes in 7-bit mode
      if mode == 1_u8
        # JIS X 0201 Roman: 0x5C = U+00A5 (¥), 0x7E = U+203E (‾)
        return DecodeResult.new(0x00A5_u32, 1) if b0 == 0x5C_u8
        return DecodeResult.new(0x203E_u32, 1) if b0 == 0x7E_u8
      end
      return DecodeResult.new(b0.to_u32, 1)
    end

    # JIS X 0208 mode (1978 or 1983 — same table)
    if mode == 2_u8 || mode == 3_u8
      return DecodeResult::TOOFEW if remaining < 2
      b1 = src.unsafe_fetch(pos + 1)

      # JIS X 0208 row/cell: both bytes 0x21-0x7E
      return DecodeResult::ILSEQ unless b0 >= 0x21_u8 && b0 <= 0x7E_u8
      return DecodeResult::ILSEQ unless b1 >= 0x21_u8 && b1 <= 0x7E_u8

      # Convert to EUC-JP coordinates (add 0x80) and look up
      lead = b0.to_i32 + 0x80  # 0xA1-0xFE
      trail = b1.to_i32 + 0x80
      idx = (lead - 0xA1) * 94 + (trail - 0xA1)
      cp = Tables::CJKJis::EUCJP_DECODE.unsafe_fetch(idx)
      return cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
    end

    # JIS X 0212 mode
    if mode == 4_u8
      return DecodeResult::TOOFEW if remaining < 2
      # JIS X 0212 not fully supported yet
      return DecodeResult::ILSEQ
    end

    DecodeResult::ILSEQ
  end

  # Encode: writes escape sequences when mode changes, then encodes character
  def self.encode(cp : UInt32, dst : Bytes, pos : Int32, state : Pointer(CodecState)) : EncodeResult
    remaining = dst.size - pos

    # ASCII range
    if cp < 0x80
      # Switch to ASCII mode if not already
      if state.value.mode != 0_u8
        return EncodeResult::TOOSMALL if remaining < 4  # ESC ( B + char
        dst.to_unsafe[pos] = 0x1B_u8
        dst.to_unsafe[pos + 1] = 0x28_u8
        dst.to_unsafe[pos + 2] = 0x42_u8
        state.value.mode = 0_u8
        dst.to_unsafe[pos + 3] = cp.to_u8
        return EncodeResult.new(4)
      end
      return EncodeResult::TOOSMALL if remaining < 1
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    # Try JIS X 0208 encode via EUC-JP table
    if cp <= 0xFFFF
      high = (cp >> 8).to_i32 & 0xFF
      page_idx = Tables::CJKJis::EUCJP_ENCODE_SUMMARY.unsafe_fetch(high)
      if page_idx != 0xFFFF_u16
        encoded = Tables::CJKJis::EUCJP_ENCODE_PAGES[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
        if encoded != 0_u16
          lead = (encoded >> 8).to_u8
          trail = (encoded & 0xFF).to_u8
          # Convert from EUC-JP to JIS (subtract 0x80)
          jis_lead = lead - 0x80
          jis_trail = trail - 0x80

          if jis_lead >= 0x21 && jis_lead <= 0x7E && jis_trail >= 0x21 && jis_trail <= 0x7E
            # Switch to JIS X 0208 mode if not already
            if state.value.mode != 3_u8
              return EncodeResult::TOOSMALL if remaining < 5  # ESC $ B + 2 chars
              dst.to_unsafe[pos] = 0x1B_u8
              dst.to_unsafe[pos + 1] = 0x24_u8
              dst.to_unsafe[pos + 2] = 0x42_u8
              state.value.mode = 3_u8
              dst.to_unsafe[pos + 3] = jis_lead
              dst.to_unsafe[pos + 4] = jis_trail
              return EncodeResult.new(5)
            end
            return EncodeResult::TOOSMALL if remaining < 2
            dst.to_unsafe[pos] = jis_lead
            dst.to_unsafe[pos + 1] = jis_trail
            return EncodeResult.new(2)
          end
        end
      end
    end

    EncodeResult::ILUNI
  end

  # Flush: ensure we return to ASCII mode at end of output
  def self.flush(dst : Bytes, pos : Int32, state : Pointer(CodecState)) : Int32
    if state.value.mode != 0_u8
      remaining = dst.size - pos
      return 0 if remaining < 3
      dst.to_unsafe[pos] = 0x1B_u8
      dst.to_unsafe[pos + 1] = 0x28_u8
      dst.to_unsafe[pos + 2] = 0x42_u8
      state.value.mode = 0_u8
      return 3
    end
    0
  end
end
