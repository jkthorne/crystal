module CharConv::Codec::UTF16
  @[AlwaysInline]
  def self.decode_be(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 2
    w1 = (src.unsafe_fetch(pos).to_u32 << 8) | src.unsafe_fetch(pos + 1).to_u32
    # Surrogate pair
    if w1 >= 0xD800 && w1 <= 0xDBFF
      return DecodeResult::TOOFEW if remaining < 4
      w2 = (src.unsafe_fetch(pos + 2).to_u32 << 8) | src.unsafe_fetch(pos + 3).to_u32
      return DecodeResult::ILSEQ unless w2 >= 0xDC00 && w2 <= 0xDFFF
      cp = 0x10000_u32 + ((w1 - 0xD800) << 10) + (w2 - 0xDC00)
      DecodeResult.new(cp, 4)
    elsif w1 >= 0xDC00 && w1 <= 0xDFFF
      # Lone low surrogate
      DecodeResult::ILSEQ
    else
      DecodeResult.new(w1, 2)
    end
  end

  @[AlwaysInline]
  def self.decode_le(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 2
    w1 = src.unsafe_fetch(pos).to_u32 | (src.unsafe_fetch(pos + 1).to_u32 << 8)
    if w1 >= 0xD800 && w1 <= 0xDBFF
      return DecodeResult::TOOFEW if remaining < 4
      w2 = src.unsafe_fetch(pos + 2).to_u32 | (src.unsafe_fetch(pos + 3).to_u32 << 8)
      return DecodeResult::ILSEQ unless w2 >= 0xDC00 && w2 <= 0xDFFF
      cp = 0x10000_u32 + ((w1 - 0xD800) << 10) + (w2 - 0xDC00)
      DecodeResult.new(cp, 4)
    elsif w1 >= 0xDC00 && w1 <= 0xDFFF
      DecodeResult::ILSEQ
    else
      DecodeResult.new(w1, 2)
    end
  end

  @[AlwaysInline]
  def self.decode_ucs2_be(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 2
    w1 = (src.unsafe_fetch(pos).to_u32 << 8) | src.unsafe_fetch(pos + 1).to_u32
    return DecodeResult::ILSEQ if w1 >= 0xD800 && w1 <= 0xDFFF
    DecodeResult.new(w1, 2)
  end

  @[AlwaysInline]
  def self.decode_ucs2_le(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 2
    w1 = src.unsafe_fetch(pos).to_u32 | (src.unsafe_fetch(pos + 1).to_u32 << 8)
    return DecodeResult::ILSEQ if w1 >= 0xD800 && w1 <= 0xDFFF
    DecodeResult.new(w1, 2)
  end

  @[AlwaysInline]
  def self.encode_be(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x10000
      return EncodeResult::TOOSMALL if dst.size - pos < 2
      return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
      dst.to_unsafe[pos] = (cp >> 8).to_u8
      dst.to_unsafe[pos + 1] = (cp & 0xFF).to_u8
      EncodeResult.new(2)
    elsif cp <= 0x10FFFF
      return EncodeResult::TOOSMALL if dst.size - pos < 4
      w1 = 0xD800_u32 + ((cp - 0x10000) >> 10)
      w2 = 0xDC00_u32 + ((cp - 0x10000) & 0x3FF)
      dst.to_unsafe[pos] = (w1 >> 8).to_u8
      dst.to_unsafe[pos + 1] = (w1 & 0xFF).to_u8
      dst.to_unsafe[pos + 2] = (w2 >> 8).to_u8
      dst.to_unsafe[pos + 3] = (w2 & 0xFF).to_u8
      EncodeResult.new(4)
    else
      EncodeResult::ILUNI
    end
  end

  @[AlwaysInline]
  def self.encode_le(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x10000
      return EncodeResult::TOOSMALL if dst.size - pos < 2
      return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
      dst.to_unsafe[pos] = (cp & 0xFF).to_u8
      dst.to_unsafe[pos + 1] = (cp >> 8).to_u8
      EncodeResult.new(2)
    elsif cp <= 0x10FFFF
      return EncodeResult::TOOSMALL if dst.size - pos < 4
      w1 = 0xD800_u32 + ((cp - 0x10000) >> 10)
      w2 = 0xDC00_u32 + ((cp - 0x10000) & 0x3FF)
      dst.to_unsafe[pos] = (w1 & 0xFF).to_u8
      dst.to_unsafe[pos + 1] = (w1 >> 8).to_u8
      dst.to_unsafe[pos + 2] = (w2 & 0xFF).to_u8
      dst.to_unsafe[pos + 3] = (w2 >> 8).to_u8
      EncodeResult.new(4)
    else
      EncodeResult::ILUNI
    end
  end

  @[AlwaysInline]
  def self.encode_ucs2_be(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    return EncodeResult::ILUNI if cp > 0xFFFF
    return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
    return EncodeResult::TOOSMALL if dst.size - pos < 2
    dst.to_unsafe[pos] = (cp >> 8).to_u8
    dst.to_unsafe[pos + 1] = (cp & 0xFF).to_u8
    EncodeResult.new(2)
  end

  @[AlwaysInline]
  def self.encode_ucs2_le(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    return EncodeResult::ILUNI if cp > 0xFFFF
    return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
    return EncodeResult::TOOSMALL if dst.size - pos < 2
    dst.to_unsafe[pos] = (cp & 0xFF).to_u8
    dst.to_unsafe[pos + 1] = (cp >> 8).to_u8
    EncodeResult.new(2)
  end
end
