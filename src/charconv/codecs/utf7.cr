module CharConv::Codec::UTF7
  # Modified Base64 alphabet per RFC 2152
  BASE64_ENCODE = StaticArray(UInt8, 64).new { |i|
    case i
    when 0..25  then ('A'.ord + i).to_u8
    when 26..51 then ('a'.ord + i - 26).to_u8
    when 52..61 then ('0'.ord + i - 52).to_u8
    when 62     then '+'.ord.to_u8
    else             '/'.ord.to_u8
    end
  }

  # Reverse lookup: byte -> 6-bit value, 0xFF = invalid
  BASE64_DECODE = begin
    table = StaticArray(UInt8, 128).new(0xFF_u8)
    64.times do |i|
      table[BASE64_ENCODE[i].to_i32] = i.to_u8
    end
    table
  end

  # Direct set: characters that pass through directly in UTF-7 encode.
  # Uses strict RFC 2152 Set D only (matching macOS iconv behavior).
  # Set O characters (! " # $ % & * ; < = > @ [ ] ^ _ ` { | } ~ \) are base64-encoded.
  DIRECT_SET = begin
    table = StaticArray(Bool, 128).new(false)
    ('A'.ord..'Z'.ord).each { |b| table[b] = true }
    ('a'.ord..'z'.ord).each { |b| table[b] = true }
    ('0'.ord..'9'.ord).each { |b| table[b] = true }
    "\'(),-./:?".each_byte { |b| table[b] = true }
    table[' '.ord] = true
    table['\t'.ord] = true
    table['\r'.ord] = true
    table['\n'.ord] = true
    table
  end

  # Decode one codepoint from UTF-7.
  # state.mode: 1=direct, 2=base64
  # state.buffer: accumulated bits (up to 32 bits)
  # state.count: number of accumulated bits
  # state.flags: bits 0-7 of stored high surrogate (0 = none)
  #   When flags != 0, we have a pending high surrogate = (flags << 8) | (buffer >> count's original bits)
  #   Actually, let's use a simpler encoding: store the high surrogate value - 0xD800 + 1 in flags
  #   (fits in u8 since max is 0xDBFF - 0xD800 = 0x3FF... no, doesn't fit in u8)
  #
  # Revised approach: The decode function scans forward from pos to find one complete codepoint.
  # It reads the state to know if we're in direct or base64 mode, and what accumulated bits we have.
  # On return, it updates state and returns the codepoint + bytes consumed from THIS call.
  def self.decode(src : Bytes, pos : Int32, state : Pointer(CodecState)) : DecodeResult
    return DecodeResult::TOOFEW if pos >= src.size

    if state.value.mode == 1_u8 # Direct mode
      byte = src.unsafe_fetch(pos)
      if byte == '+'.ord.to_u8
        # Check for +-
        if pos + 1 < src.size && src.unsafe_fetch(pos + 1) == '-'.ord.to_u8
          return DecodeResult.new('+'.ord.to_u32, 2)
        end
        # Enter base64 mode
        state.value.mode = 2_u8
        state.value.buffer = 0_u32
        state.value.count = 0_u8
        state.value.flags = 0_u8
        # Now scan forward from pos+1 to find first complete codepoint
        return scan_base64_codepoint(src, pos, pos + 1, state)
      elsif byte < 0x80_u8
        return DecodeResult.new(byte.to_u32, 1)
      else
        return DecodeResult::ILSEQ
      end
    else # Base64 mode (mode == 2)
      return scan_base64_codepoint(src, pos, pos, state)
    end
  end

  # Scan from `scan_start` consuming base64 chars until we have a complete 16-bit code unit.
  # `call_start` is where this decode_one call started (for computing bytes consumed).
  private def self.scan_base64_codepoint(src : Bytes, call_start : Int32, scan_start : Int32, state : Pointer(CodecState)) : DecodeResult
    i = scan_start
    buffer = state.value.buffer
    bits = state.value.count.to_i32

    while i < src.size
      byte = src.unsafe_fetch(i)

      if byte < 0x80_u8 && BASE64_DECODE[byte.to_i32] != 0xFF_u8
        buffer = (buffer << 6) | BASE64_DECODE[byte.to_i32].to_u32
        bits += 6
        i += 1

        if bits >= 16
          bits -= 16
          w = (buffer >> bits) & 0xFFFF
          if bits > 0
            buffer &= (1_u32 << bits) - 1
          else
            buffer = 0_u32
          end

          # Check for surrogate pair
          if w >= 0xD800 && w <= 0xDBFF
            # High surrogate — need to find low surrogate in the same base64 stream
            result = scan_low_surrogate(src, i, w, buffer, bits, call_start, state)
            return result
          elsif w >= 0xDC00 && w <= 0xDFFF
            return DecodeResult::ILSEQ
          else
            # Look ahead: if next byte is '-' terminator or non-base64, consume it
            # to avoid leaving a dangling terminator
            if i < src.size
              nb = src.unsafe_fetch(i)
              if nb == '-'.ord.to_u8
                i += 1
                state.value.mode = 1_u8
                state.value.buffer = 0_u32
                state.value.count = 0_u8
              elsif nb >= 0x80_u8 || BASE64_DECODE[nb.to_i32] == 0xFF_u8
                # Non-base64 char terminates implicitly (don't consume it — direct mode will handle)
                state.value.mode = 1_u8
                state.value.buffer = 0_u32
                state.value.count = 0_u8
              else
                state.value.buffer = buffer
                state.value.count = bits.to_u8
                # Stay in base64 mode
              end
            else
              state.value.buffer = buffer
              state.value.count = bits.to_u8
            end
            return DecodeResult.new(w, i - call_start)
          end
        end
      else
        # Non-base64 char: exit base64 mode
        consumed_terminator = 0
        if byte == '-'.ord.to_u8
          i += 1
          consumed_terminator = 1
        end
        state.value.mode = 1_u8
        state.value.buffer = 0_u32
        state.value.count = 0_u8

        # We exited base64 without producing a character from accumulated bits.
        # Now we're in direct mode. If there's a character available, decode it.
        if i < src.size
          nb = src.unsafe_fetch(i)
          if nb == '+'.ord.to_u8
            if i + 1 < src.size && src.unsafe_fetch(i + 1) == '-'.ord.to_u8
              return DecodeResult.new('+'.ord.to_u32, i + 2 - call_start)
            end
            state.value.mode = 2_u8
            state.value.buffer = 0_u32
            state.value.count = 0_u8
            return scan_base64_codepoint(src, call_start, i + 1, state)
          elsif nb < 0x80_u8
            return DecodeResult.new(nb.to_u32, i + 1 - call_start)
          else
            return DecodeResult::ILSEQ
          end
        end
        return DecodeResult::TOOFEW
      end
    end

    # Ran out of input in base64 mode
    state.value.buffer = buffer
    state.value.count = bits.to_u8
    DecodeResult::TOOFEW
  end

  private def self.scan_low_surrogate(src : Bytes, i : Int32, high_w : UInt32, buffer : UInt32, bits : Int32, call_start : Int32, state : Pointer(CodecState)) : DecodeResult
    while i < src.size
      byte = src.unsafe_fetch(i)

      if byte < 0x80_u8 && BASE64_DECODE[byte.to_i32] != 0xFF_u8
        buffer = (buffer << 6) | BASE64_DECODE[byte.to_i32].to_u32
        bits += 6
        i += 1

        if bits >= 16
          bits -= 16
          w2 = (buffer >> bits) & 0xFFFF
          if bits > 0
            buffer &= (1_u32 << bits) - 1
          else
            buffer = 0_u32
          end

          if w2 >= 0xDC00 && w2 <= 0xDFFF
            cp = 0x10000_u32 + ((high_w - 0xD800) << 10) + (w2 - 0xDC00)
            # Look ahead for terminator
            if i < src.size
              nb = src.unsafe_fetch(i)
              if nb == '-'.ord.to_u8
                i += 1
                state.value.mode = 1_u8
                state.value.buffer = 0_u32
                state.value.count = 0_u8
              elsif nb >= 0x80_u8 || BASE64_DECODE[nb.to_i32] == 0xFF_u8
                state.value.mode = 1_u8
                state.value.buffer = 0_u32
                state.value.count = 0_u8
              else
                state.value.buffer = buffer
                state.value.count = bits.to_u8
              end
            else
              state.value.buffer = buffer
              state.value.count = bits.to_u8
            end
            return DecodeResult.new(cp, i - call_start)
          else
            return DecodeResult::ILSEQ
          end
        end
      else
        # Non-base64 before low surrogate
        return DecodeResult::ILSEQ
      end
    end
    DecodeResult::TOOFEW
  end

  # Encode one codepoint to UTF-7.
  # state.mode: 1=direct, 2=base64
  # state.buffer: accumulated bits
  # state.count: number of accumulated bits
  def self.encode(cp : UInt32, dst : Bytes, pos : Int32, state : Pointer(CodecState)) : EncodeResult
    return EncodeResult::ILUNI if cp > 0x10FFFF
    remaining = dst.size - pos

    if cp < 0x80 && DIRECT_SET[cp.to_i32]
      if state.value.mode == 2_u8
        # Flush base64 and switch to direct
        # Omit '-' terminator if the direct char is not a base64 alphabet char
        needs_dash = cp < 0x80 && BASE64_DECODE[cp.to_i32] != 0xFF_u8
        written = flush_base64_smart(dst, pos, state, needs_dash)
        return EncodeResult::TOOSMALL if pos + written >= dst.size
        dst.to_unsafe[pos + written] = cp.to_u8
        return EncodeResult.new(written + 1)
      else
        return EncodeResult::TOOSMALL if remaining < 1
        dst.to_unsafe[pos] = cp.to_u8
        return EncodeResult.new(1)
      end
    end

    # Need base64 encoding
    written = 0
    if state.value.mode == 1_u8
      # Enter base64 mode — write '+'
      return EncodeResult::TOOSMALL if remaining < 4 # need at least '+' + some base64
      dst.to_unsafe[pos] = '+'.ord.to_u8
      state.value.mode = 2_u8
      state.value.buffer = 0_u32
      state.value.count = 0_u8
      written = 1
    end

    # Encode as UTF-16BE code units into base64
    if cp < 0x10000
      return encode_base64_units(cp.to_u16, dst, pos + written, state, written)
    else
      # Surrogate pair
      w1 = (0xD800_u32 + ((cp - 0x10000) >> 10)).to_u16
      w2 = (0xDC00_u32 + ((cp - 0x10000) & 0x3FF)).to_u16
      r1 = encode_base64_units(w1, dst, pos + written, state, written)
      return r1 unless r1.ok?
      offset = r1.status
      r2 = encode_base64_units(w2, dst, pos + offset, state, offset)
      return r2 unless r2.ok?
      return EncodeResult.new(r2.status)
    end
  end

  private def self.encode_base64_units(unit : UInt16, dst : Bytes, pos : Int32, state : Pointer(CodecState), total_written : Int32) : EncodeResult
    buffer = state.value.buffer
    bits = state.value.count.to_i32

    buffer = (buffer << 16) | unit.to_u32
    bits += 16

    written = 0
    remaining = dst.size - pos

    while bits >= 6
      return EncodeResult::TOOSMALL if written >= remaining
      bits -= 6
      idx = ((buffer >> bits) & 0x3F).to_i32
      dst.to_unsafe[pos + written] = BASE64_ENCODE[idx]
      written += 1
    end

    if bits > 0
      state.value.buffer = buffer & ((1_u32 << bits) - 1)
    else
      state.value.buffer = 0_u32
    end
    state.value.count = bits.to_u8
    EncodeResult.new(total_written + written)
  end

  # Flush remaining base64 bits + emit '-' (used for end-of-stream)
  def self.flush_base64(dst : Bytes, pos : Int32, state : Pointer(CodecState)) : Int32
    flush_base64_smart(dst, pos, state, true)
  end

  # Flush base64 state. If emit_dash is false, omit the '-' terminator.
  def self.flush_base64_smart(dst : Bytes, pos : Int32, state : Pointer(CodecState), emit_dash : Bool) : Int32
    written = 0
    ptr = dst.to_unsafe + pos

    if state.value.count > 0
      bits = state.value.count.to_i32
      idx = ((state.value.buffer << (6 - bits)) & 0x3F).to_i32
      ptr[written] = BASE64_ENCODE[idx]
      written += 1
    end

    if emit_dash
      ptr[written] = '-'.ord.to_u8
      written += 1
    end

    state.value.buffer = 0_u32
    state.value.count = 0_u8
    state.value.mode = 1_u8
    written
  end
end
