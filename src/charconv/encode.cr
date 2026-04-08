# Encode functions: UCS-4 codepoint → target bytes.
#
# Each method writes one encoded character into *dst* at byte offset *pos*
# and returns an `EncodeResult`. Specialized encoders exist for ASCII, UTF-8,
# ISO-8859-1, and a generic table-driven path for all other single-byte
# encodings. CJK and stateful encoders live in `Codec::*`.
module CharConv::Encode
  @[AlwaysInline]
  def self.ascii(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    return EncodeResult::TOOSMALL if pos >= dst.size
    if cp < 0x80
      dst.to_unsafe[pos] = cp.to_u8
      EncodeResult.new(1)
    else
      EncodeResult::ILUNI
    end
  end

  @[AlwaysInline]
  def self.utf8(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    remaining = dst.size - pos
    ptr = dst.to_unsafe + pos

    if cp < 0x80
      return EncodeResult::TOOSMALL if remaining < 1
      ptr[0] = cp.to_u8
      EncodeResult.new(1)
    elsif cp < 0x800
      return EncodeResult::TOOSMALL if remaining < 2
      ptr[0] = (0xC0 | (cp >> 6)).to_u8
      ptr[1] = (0x80 | (cp & 0x3F)).to_u8
      EncodeResult.new(2)
    elsif cp < 0x10000
      return EncodeResult::TOOSMALL if remaining < 3
      ptr[0] = (0xE0 | (cp >> 12)).to_u8
      ptr[1] = (0x80 | ((cp >> 6) & 0x3F)).to_u8
      ptr[2] = (0x80 | (cp & 0x3F)).to_u8
      EncodeResult.new(3)
    elsif cp <= 0x10FFFF
      return EncodeResult::TOOSMALL if remaining < 4
      ptr[0] = (0xF0 | (cp >> 18)).to_u8
      ptr[1] = (0x80 | ((cp >> 12) & 0x3F)).to_u8
      ptr[2] = (0x80 | ((cp >> 6) & 0x3F)).to_u8
      ptr[3] = (0x80 | (cp & 0x3F)).to_u8
      EncodeResult.new(4)
    else
      EncodeResult::ILUNI
    end
  end

  @[AlwaysInline]
  def self.iso_8859_1(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    return EncodeResult::TOOSMALL if pos >= dst.size
    if cp <= 0xFF
      dst.to_unsafe[pos] = cp.to_u8
      EncodeResult.new(1)
    else
      EncodeResult::ILUNI
    end
  end

  # Generic single-byte encode using a 64KB lookup table (codepoint → byte).
  # Byte 0 means not representable (except codepoint 0 → byte 0 is valid).
  @[AlwaysInline]
  def self.single_byte_table(cp : UInt32, dst : Bytes, pos : Int32, table : Pointer(UInt8)) : EncodeResult
    return EncodeResult::TOOSMALL if pos >= dst.size
    return EncodeResult::ILUNI if cp > 0xFFFF
    byte = table[cp]
    if byte == 0 && cp != 0
      EncodeResult::ILUNI
    else
      dst.to_unsafe[pos] = byte
      EncodeResult.new(1)
    end
  end
end
