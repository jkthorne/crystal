module CharConv::Codec::UTF32
  @[AlwaysInline]
  def self.decode_be(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 4
    cp = (src.unsafe_fetch(pos).to_u32 << 24) |
         (src.unsafe_fetch(pos + 1).to_u32 << 16) |
         (src.unsafe_fetch(pos + 2).to_u32 << 8) |
         src.unsafe_fetch(pos + 3).to_u32
    return DecodeResult::ILSEQ if cp > 0x10FFFF
    return DecodeResult::ILSEQ if cp >= 0xD800 && cp <= 0xDFFF
    DecodeResult.new(cp, 4)
  end

  @[AlwaysInline]
  def self.decode_le(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 4
    cp = src.unsafe_fetch(pos).to_u32 |
         (src.unsafe_fetch(pos + 1).to_u32 << 8) |
         (src.unsafe_fetch(pos + 2).to_u32 << 16) |
         (src.unsafe_fetch(pos + 3).to_u32 << 24)
    return DecodeResult::ILSEQ if cp > 0x10FFFF
    return DecodeResult::ILSEQ if cp >= 0xD800 && cp <= 0xDFFF
    DecodeResult.new(cp, 4)
  end

  @[AlwaysInline]
  def self.encode_be(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    return EncodeResult::ILUNI if cp > 0x10FFFF
    return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
    return EncodeResult::TOOSMALL if dst.size - pos < 4
    dst.to_unsafe[pos] = (cp >> 24).to_u8
    dst.to_unsafe[pos + 1] = ((cp >> 16) & 0xFF).to_u8
    dst.to_unsafe[pos + 2] = ((cp >> 8) & 0xFF).to_u8
    dst.to_unsafe[pos + 3] = (cp & 0xFF).to_u8
    EncodeResult.new(4)
  end

  @[AlwaysInline]
  def self.encode_le(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    return EncodeResult::ILUNI if cp > 0x10FFFF
    return EncodeResult::ILUNI if cp >= 0xD800 && cp <= 0xDFFF
    return EncodeResult::TOOSMALL if dst.size - pos < 4
    dst.to_unsafe[pos] = (cp & 0xFF).to_u8
    dst.to_unsafe[pos + 1] = ((cp >> 8) & 0xFF).to_u8
    dst.to_unsafe[pos + 2] = ((cp >> 16) & 0xFF).to_u8
    dst.to_unsafe[pos + 3] = (cp >> 24).to_u8
    EncodeResult.new(4)
  end
end
