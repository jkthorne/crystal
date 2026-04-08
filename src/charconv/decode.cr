# Decode functions: source bytes → UCS-4 codepoint.
#
# Each method reads one character from *src* at byte offset *pos* and returns
# a `DecodeResult`. Specialized decoders exist for ASCII, UTF-8, ISO-8859-1,
# and a generic table-driven path for all other single-byte encodings.
# CJK and stateful decoders live in `Codec::*`.
module CharConv::Decode
  @[AlwaysInline]
  def self.ascii(src : Bytes, pos : Int32) : DecodeResult
    return DecodeResult::TOOFEW if pos >= src.size
    byte = src.unsafe_fetch(pos)
    if byte < 0x80_u8
      DecodeResult.new(byte.to_u32, 1)
    else
      DecodeResult::ILSEQ
    end
  end

  @[AlwaysInline]
  def self.utf8(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining <= 0

    b0 = src.unsafe_fetch(pos).to_u32

    # 1-byte (ASCII)
    if b0 < 0x80
      return DecodeResult.new(b0, 1)
    end

    # Reject invalid lead bytes
    return DecodeResult::ILSEQ if b0 < 0xC2 # 0x80-0xBF are continuations, 0xC0-0xC1 are overlong
    return DecodeResult::ILSEQ if b0 > 0xF4

    # 2-byte sequence: 110xxxxx 10xxxxxx
    if b0 < 0xE0
      return DecodeResult::TOOFEW if remaining < 2
      b1 = src.unsafe_fetch(pos + 1).to_u32
      return DecodeResult::ILSEQ unless b1 & 0xC0 == 0x80
      cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
      return DecodeResult.new(cp, 2)
    end

    # 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
    if b0 < 0xF0
      return DecodeResult::TOOFEW if remaining < 3
      b1 = src.unsafe_fetch(pos + 1).to_u32
      return DecodeResult::ILSEQ unless b1 & 0xC0 == 0x80
      b2 = src.unsafe_fetch(pos + 2).to_u32
      return DecodeResult::ILSEQ unless b2 & 0xC0 == 0x80
      cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
      # Reject overlong
      return DecodeResult::ILSEQ if cp < 0x0800
      # Reject surrogates U+D800..U+DFFF
      return DecodeResult::ILSEQ if cp >= 0xD800 && cp <= 0xDFFF
      return DecodeResult.new(cp, 3)
    end

    # 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    return DecodeResult::TOOFEW if remaining < 4
    b1 = src.unsafe_fetch(pos + 1).to_u32
    return DecodeResult::ILSEQ unless b1 & 0xC0 == 0x80
    b2 = src.unsafe_fetch(pos + 2).to_u32
    return DecodeResult::ILSEQ unless b2 & 0xC0 == 0x80
    b3 = src.unsafe_fetch(pos + 3).to_u32
    return DecodeResult::ILSEQ unless b3 & 0xC0 == 0x80
    cp = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
    # Reject overlong
    return DecodeResult::ILSEQ if cp < 0x10000
    # Reject > U+10FFFF
    return DecodeResult::ILSEQ if cp > 0x10FFFF
    DecodeResult.new(cp, 4)
  end

  @[AlwaysInline]
  def self.iso_8859_1(src : Bytes, pos : Int32) : DecodeResult
    return DecodeResult::TOOFEW if pos >= src.size
    DecodeResult.new(src.unsafe_fetch(pos).to_u32, 1)
  end

  # Generic single-byte decode using a 256-entry table (full byte range).
  @[AlwaysInline]
  def self.single_byte_table(src : Bytes, pos : Int32, table : Pointer(UInt16)) : DecodeResult
    return DecodeResult::TOOFEW if pos >= src.size
    byte = src.unsafe_fetch(pos)
    cp = table[byte].to_u32
    cp == 0xFFFF ? DecodeResult::ILSEQ : DecodeResult.new(cp, 1)
  end
end
