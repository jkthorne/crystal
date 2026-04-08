module CharConv::Codec::C99
  @[AlwaysInline]
  def self.decode(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining <= 0
    byte = src.unsafe_fetch(pos)

    if byte == '\\'.ord.to_u8 && remaining >= 2
      next_byte = src.unsafe_fetch(pos + 1)
      if next_byte == 'u'.ord.to_u8
        # \uXXXX — 4 hex digits
        return DecodeResult::TOOFEW if remaining < 6
        cp = parse_hex4(src, pos + 2)
        return DecodeResult::ILSEQ if cp < 0
        return DecodeResult.new(cp.to_u32, 6)
      elsif next_byte == 'U'.ord.to_u8
        # \UXXXXXXXX — 8 hex digits
        return DecodeResult::TOOFEW if remaining < 10
        cp = parse_hex8(src, pos + 2)
        return DecodeResult::ILSEQ if cp < 0
        return DecodeResult::ILSEQ if cp.to_u32 > 0x10FFFF
        return DecodeResult::ILSEQ if cp.to_u32 >= 0xD800 && cp.to_u32 <= 0xDFFF
        return DecodeResult.new(cp.to_u32, 10)
      end
    end

    # Direct pass-through for ASCII
    if byte < 0x80_u8
      return DecodeResult.new(byte.to_u32, 1)
    end

    DecodeResult::ILSEQ
  end

  @[AlwaysInline]
  def self.encode(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    remaining = dst.size - pos
    ptr = dst.to_unsafe + pos

    if cp < 0x80
      return EncodeResult::TOOSMALL if remaining < 1
      ptr[0] = cp.to_u8
      return EncodeResult.new(1)
    elsif cp <= 0xFFFF
      # \uXXXX
      return EncodeResult::TOOSMALL if remaining < 6
      ptr[0] = '\\'.ord.to_u8
      ptr[1] = 'u'.ord.to_u8
      write_hex4(ptr + 2, cp)
      return EncodeResult.new(6)
    elsif cp <= 0x10FFFF
      # \UXXXXXXXX
      return EncodeResult::TOOSMALL if remaining < 10
      ptr[0] = '\\'.ord.to_u8
      ptr[1] = 'U'.ord.to_u8
      write_hex8(ptr + 2, cp)
      return EncodeResult.new(10)
    else
      return EncodeResult::ILUNI
    end
  end

  HEX_CHARS = StaticArray['0'.ord.to_u8, '1'.ord.to_u8, '2'.ord.to_u8, '3'.ord.to_u8,
                           '4'.ord.to_u8, '5'.ord.to_u8, '6'.ord.to_u8, '7'.ord.to_u8,
                           '8'.ord.to_u8, '9'.ord.to_u8, 'a'.ord.to_u8, 'b'.ord.to_u8,
                           'c'.ord.to_u8, 'd'.ord.to_u8, 'e'.ord.to_u8, 'f'.ord.to_u8]

  @[AlwaysInline]
  def self.write_hex4(ptr : Pointer(UInt8), value : UInt32)
    ptr[0] = HEX_CHARS[(value >> 12) & 0xF]
    ptr[1] = HEX_CHARS[(value >> 8) & 0xF]
    ptr[2] = HEX_CHARS[(value >> 4) & 0xF]
    ptr[3] = HEX_CHARS[value & 0xF]
  end

  @[AlwaysInline]
  private def self.write_hex8(ptr : Pointer(UInt8), value : UInt32)
    ptr[0] = HEX_CHARS[(value >> 28) & 0xF]
    ptr[1] = HEX_CHARS[(value >> 24) & 0xF]
    ptr[2] = HEX_CHARS[(value >> 20) & 0xF]
    ptr[3] = HEX_CHARS[(value >> 16) & 0xF]
    ptr[4] = HEX_CHARS[(value >> 12) & 0xF]
    ptr[5] = HEX_CHARS[(value >> 8) & 0xF]
    ptr[6] = HEX_CHARS[(value >> 4) & 0xF]
    ptr[7] = HEX_CHARS[value & 0xF]
  end

  @[AlwaysInline]
  def self.parse_hex4(src : Bytes, pos : Int32) : Int32
    result = 0_u32
    4.times do |i|
      byte = src.unsafe_fetch(pos + i)
      d = hex_digit(byte)
      return -1 if d < 0
      result = (result << 4) | d.to_u32
    end
    result.to_i32
  end

  @[AlwaysInline]
  private def self.parse_hex8(src : Bytes, pos : Int32) : Int64
    result = 0_u64
    8.times do |i|
      byte = src.unsafe_fetch(pos + i)
      d = hex_digit(byte)
      return -1_i64 if d < 0
      result = (result << 4) | d.to_u64
    end
    result.to_i64
  end

  @[AlwaysInline]
  def self.hex_digit(byte : UInt8) : Int32
    if byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8
      (byte - '0'.ord.to_u8).to_i32
    elsif byte >= 'a'.ord.to_u8 && byte <= 'f'.ord.to_u8
      (byte - 'a'.ord.to_u8 + 10).to_i32
    elsif byte >= 'A'.ord.to_u8 && byte <= 'F'.ord.to_u8
      (byte - 'A'.ord.to_u8 + 10).to_i32
    else
      -1
    end
  end
end

module CharConv::Codec::Java
  @[AlwaysInline]
  def self.decode(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining <= 0
    byte = src.unsafe_fetch(pos)

    if byte == '\\'.ord.to_u8 && remaining >= 2
      next_byte = src.unsafe_fetch(pos + 1)
      if next_byte == 'u'.ord.to_u8
        return DecodeResult::TOOFEW if remaining < 6
        cp = C99.parse_hex4(src, pos + 2)
        return DecodeResult::ILSEQ if cp < 0
        w1 = cp.to_u32

        # Check for surrogate pair
        if w1 >= 0xD800 && w1 <= 0xDBFF
          # Need \uXXXX for low surrogate
          return DecodeResult::TOOFEW if remaining < 12
          return DecodeResult::ILSEQ unless src.unsafe_fetch(pos + 6) == '\\'.ord.to_u8
          return DecodeResult::ILSEQ unless src.unsafe_fetch(pos + 7) == 'u'.ord.to_u8
          cp2 = C99.parse_hex4(src, pos + 8)
          return DecodeResult::ILSEQ if cp2 < 0
          w2 = cp2.to_u32
          return DecodeResult::ILSEQ unless w2 >= 0xDC00 && w2 <= 0xDFFF
          full_cp = 0x10000_u32 + ((w1 - 0xD800) << 10) + (w2 - 0xDC00)
          return DecodeResult.new(full_cp, 12)
        elsif w1 >= 0xDC00 && w1 <= 0xDFFF
          # Lone low surrogate
          return DecodeResult::ILSEQ
        end

        return DecodeResult.new(w1, 6)
      end
    end

    # Direct pass-through for ASCII
    if byte < 0x80_u8
      return DecodeResult.new(byte.to_u32, 1)
    end

    DecodeResult::ILSEQ
  end

  @[AlwaysInline]
  def self.encode(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    remaining = dst.size - pos
    ptr = dst.to_unsafe + pos

    if cp < 0x80
      return EncodeResult::TOOSMALL if remaining < 1
      ptr[0] = cp.to_u8
      return EncodeResult.new(1)
    elsif cp <= 0xFFFF
      return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
      # \uXXXX
      return EncodeResult::TOOSMALL if remaining < 6
      ptr[0] = '\\'.ord.to_u8
      ptr[1] = 'u'.ord.to_u8
      C99.write_hex4(ptr + 2, cp)
      return EncodeResult.new(6)
    elsif cp <= 0x10FFFF
      # Surrogate pair: \uXXXX\uXXXX
      return EncodeResult::TOOSMALL if remaining < 12
      w1 = 0xD800_u32 + ((cp - 0x10000) >> 10)
      w2 = 0xDC00_u32 + ((cp - 0x10000) & 0x3FF)
      ptr[0] = '\\'.ord.to_u8
      ptr[1] = 'u'.ord.to_u8
      C99.write_hex4(ptr + 2, w1)
      ptr[6] = '\\'.ord.to_u8
      ptr[7] = 'u'.ord.to_u8
      C99.write_hex4(ptr + 8, w2)
      return EncodeResult.new(12)
    else
      return EncodeResult::ILUNI
    end
  end
end
