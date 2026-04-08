# Stateless CJK codecs: EUC-JP, Shift_JIS, CP932, GBK, EUC-CN (GB2312),
# Big5, CP950, Big5-HKSCS, EUC-KR, CP949, JOHAB, EUC-TW
#
# Each encoding uses a 2D decode table (lead × trail → codepoint) and a
# two-level page table for encode (codepoint → 2 bytes).

module CharConv::Codec::CJK
  # -----------------------------------------------------------------------
  # Generic 2D table decode: lead + trail → codepoint
  # -----------------------------------------------------------------------
  @[AlwaysInline]
  def self.decode_2byte(src : Bytes, pos : Int32,
                        decode_table : Slice(UInt16),
                        lead_min : Int32, lead_max : Int32,
                        trail_min : Int32, trail_max : Int32,
                        trail_count : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    lead = src.unsafe_fetch(pos).to_i32

    # Check if lead byte is in range
    return DecodeResult::ILSEQ unless lead >= lead_min && lead <= lead_max
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= trail_min && trail <= trail_max

    idx = (lead - lead_min) * trail_count + (trail - trail_min)
    cp = decode_table.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  # -----------------------------------------------------------------------
  # Generic 2-level page table encode: codepoint → 2 bytes
  # -----------------------------------------------------------------------
  @[AlwaysInline]
  def self.encode_2byte(cp : UInt32, dst : Bytes, pos : Int32,
                        summary : Slice(UInt16),
                        pages : Indexable(Slice(UInt16))) : EncodeResult
    return EncodeResult::ILUNI if cp > 0xFFFF
    remaining = dst.size - pos
    return EncodeResult::TOOSMALL if remaining < 2

    high = (cp >> 8).to_i32 & 0xFF
    page_idx = summary.unsafe_fetch(high)
    return EncodeResult::ILUNI if page_idx == 0xFFFF_u16

    encoded = pages[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
    return EncodeResult::ILUNI if encoded == 0_u16

    dst.to_unsafe[pos] = (encoded >> 8).to_u8
    dst.to_unsafe[pos + 1] = (encoded & 0xFF).to_u8
    EncodeResult.new(2)
  end

  # =======================================================================
  # EUC-JP
  # =======================================================================

  def self.decode_euc_jp(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    # ASCII
    if b0 < 0x80
      return DecodeResult.new(b0.to_u32, 1)
    end

    # Half-width katakana: 0x8E + byte (JIS X 0201)
    if b0 == 0x8E_u8
      return DecodeResult::TOOFEW if remaining < 2
      b1 = src.unsafe_fetch(pos + 1)
      return DecodeResult::ILSEQ unless b1 >= 0xA1_u8 && b1 <= 0xDF_u8
      # JIS X 0201 katakana: 0xA1-0xDF → U+FF61-U+FF9F (fixed offset)
      cp = (0xFF61_u32 + b1.to_u32 - 0xA1_u32)
      return DecodeResult.new(cp, 2)
    end

    # JIS X 0212 (3-byte): 0x8F + lead + trail
    if b0 == 0x8F_u8
      return DecodeResult::TOOFEW if remaining < 3
      # JIS X 0212 not in our table yet — report ILSEQ for now
      # (very rarely used, can be added later)
      return DecodeResult::ILSEQ
    end

    # JIS X 0208: lead 0xA1-0xFE, trail 0xA1-0xFE
    return DecodeResult::ILSEQ unless b0 >= 0xA1_u8 && b0 <= 0xFE_u8
    return DecodeResult::TOOFEW if remaining < 2
    b1 = src.unsafe_fetch(pos + 1)
    return DecodeResult::ILSEQ unless b1 >= 0xA1_u8 && b1 <= 0xFE_u8

    idx = (b0.to_i32 - 0xA1) * 94 + (b1.to_i32 - 0xA1)
    cp = Tables::CJKJis::EUCJP_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_euc_jp(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    # ASCII
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    # Half-width katakana: U+FF61..U+FF9F → 0x8E + (0xA1 + offset)
    if cp >= 0xFF61 && cp <= 0xFF9F
      return EncodeResult::TOOSMALL if dst.size - pos < 2
      dst.to_unsafe[pos] = 0x8E_u8
      dst.to_unsafe[pos + 1] = (0xA1_u32 + cp - 0xFF61_u32).to_u8
      return EncodeResult.new(2)
    end

    # JIS X 0208 via page table
    remaining = dst.size - pos
    return EncodeResult::TOOSMALL if remaining < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKJis::EUCJP_ENCODE_SUMMARY,
      Tables::CJKJis::EUCJP_ENCODE_PAGES)
  end

  # =======================================================================
  # Shift_JIS
  # =======================================================================

  def self.decode_shift_jis(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    # Single-byte range: use SINGLE_DECODE table (handles ASCII with yen sign, katakana, etc.)
    if b0 < 0x80 || (b0 >= 0xA1_u8 && b0 <= 0xDF_u8)
      cp = Tables::CJKJis::SHIFTJIS_SINGLE_DECODE[b0.to_i32]
      return cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 1)
    end

    # 0x80 is undefined in standard Shift_JIS
    return DecodeResult::ILSEQ if b0 == 0x80_u8

    # Two-byte: lead 0x81-0x9F, 0xE0-0xEF; trail 0x40-0xFC
    lead = b0.to_i32
    unless (lead >= 0x81 && lead <= 0x9F) || (lead >= 0xE0 && lead <= 0xEF)
      return DecodeResult::ILSEQ
    end
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x40 && trail <= 0xFC && trail != 0x7F

    idx = (lead - 0x81) * (0xFC - 0x40 + 1) + (trail - 0x40)
    cp = Tables::CJKJis::SHIFTJIS_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_shift_jis(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    # Check single-byte encode pairs first (handles U+00A5→0x5C, U+203E→0x7E, katakana)
    Tables::CJKJis::SHIFTJIS_SINGLE_ENCODE_PAIRS.each do |(ucp, byte)|
      if ucp.to_u32 == cp
        return EncodeResult::TOOSMALL if pos >= dst.size
        dst.to_unsafe[pos] = byte
        return EncodeResult.new(1)
      end
    end

    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKJis::SHIFTJIS_ENCODE_SUMMARY,
      Tables::CJKJis::SHIFTJIS_ENCODE_PAGES)
  end

  # =======================================================================
  # CP932 (Microsoft Shift_JIS superset)
  # =======================================================================

  def self.decode_cp932(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    # Single-byte range (ASCII + katakana)
    if b0 < 0x80 || (b0 >= 0xA1_u8 && b0 <= 0xDF_u8)
      cp = Tables::CJKJis::CP932_SINGLE_DECODE[b0.to_i32]
      return cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 1)
    end

    return DecodeResult::ILSEQ if b0 == 0x80_u8

    # Two-byte: lead 0x81-0xFC; trail 0x40-0xFC
    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x81 && lead <= 0xFC
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x40 && trail <= 0xFC && trail != 0x7F

    idx = (lead - 0x81) * (0xFC - 0x40 + 1) + (trail - 0x40)
    cp = Tables::CJKJis::CP932_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_cp932(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    Tables::CJKJis::CP932_SINGLE_ENCODE_PAIRS.each do |(ucp, byte)|
      if ucp.to_u32 == cp
        return EncodeResult::TOOSMALL if pos >= dst.size
        dst.to_unsafe[pos] = byte
        return EncodeResult.new(1)
      end
    end

    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKJis::CP932_ENCODE_SUMMARY,
      Tables::CJKJis::CP932_ENCODE_PAGES)
  end

  # =======================================================================
  # GBK
  # =======================================================================

  def self.decode_gbk(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    # Two-byte: lead 0x81-0xFE, trail 0x40-0xFE (0x7F is gap)
    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x81 && lead <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x40 && trail <= 0xFE && trail != 0x7F

    idx = (lead - Tables::CJKGB::GBK_LEAD_MIN) * Tables::CJKGB::GBK_TRAIL_COUNT + (trail - Tables::CJKGB::GBK_TRAIL_MIN)
    cp = Tables::CJKGB::GBK_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_gbk(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKGB::GBK_ENCODE_SUMMARY,
      Tables::CJKGB::GBK_ENCODE_PAGES)
  end

  # =======================================================================
  # EUC-CN (= GB2312 in EUC wrapper)
  # =======================================================================

  def self.decode_euc_cn(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0xA1 && lead <= 0xF7
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0xA1 && trail <= 0xFE

    idx = (lead - Tables::CJKGB::EUCCN_LEAD_MIN) * Tables::CJKGB::EUCCN_TRAIL_COUNT + (trail - Tables::CJKGB::EUCCN_TRAIL_MIN)
    cp = Tables::CJKGB::EUCCN_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_euc_cn(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKGB::EUCCN_ENCODE_SUMMARY,
      Tables::CJKGB::EUCCN_ENCODE_PAGES)
  end

  # =======================================================================
  # Big5
  # =======================================================================

  def self.decode_big5(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x81 && lead <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x40 && trail <= 0xFE && trail != 0x7F

    idx = (lead - Tables::CJKBig5::BIG5_LEAD_MIN) * Tables::CJKBig5::BIG5_TRAIL_COUNT + (trail - Tables::CJKBig5::BIG5_TRAIL_MIN)
    cp = Tables::CJKBig5::BIG5_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_big5(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKBig5::BIG5_ENCODE_SUMMARY,
      Tables::CJKBig5::BIG5_ENCODE_PAGES)
  end

  # =======================================================================
  # CP950 (Microsoft Big5 superset)
  # =======================================================================

  def self.decode_cp950(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x81 && lead <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x40 && trail <= 0xFE && trail != 0x7F

    idx = (lead - Tables::CJKBig5::CP950_LEAD_MIN) * Tables::CJKBig5::CP950_TRAIL_COUNT + (trail - Tables::CJKBig5::CP950_TRAIL_MIN)
    cp = Tables::CJKBig5::CP950_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_cp950(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKBig5::CP950_ENCODE_SUMMARY,
      Tables::CJKBig5::CP950_ENCODE_PAGES)
  end

  # =======================================================================
  # Big5-HKSCS
  # =======================================================================

  def self.decode_big5_hkscs(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x81 && lead <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x40 && trail <= 0xFE && trail != 0x7F

    idx = (lead - Tables::CJKBig5::BIG5HKSCS_LEAD_MIN) * Tables::CJKBig5::BIG5HKSCS_TRAIL_COUNT + (trail - Tables::CJKBig5::BIG5HKSCS_TRAIL_MIN)
    cp = Tables::CJKBig5::BIG5HKSCS_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_big5_hkscs(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKBig5::BIG5HKSCS_ENCODE_SUMMARY,
      Tables::CJKBig5::BIG5HKSCS_ENCODE_PAGES)
  end

  # =======================================================================
  # EUC-KR
  # =======================================================================

  def self.decode_euc_kr(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0xA1 && lead <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0xA1 && trail <= 0xFE

    idx = (lead - Tables::CJKKSC::EUCKR_LEAD_MIN) * Tables::CJKKSC::EUCKR_TRAIL_COUNT + (trail - Tables::CJKKSC::EUCKR_TRAIL_MIN)
    cp = Tables::CJKKSC::EUCKR_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_euc_kr(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKKSC::EUCKR_ENCODE_SUMMARY,
      Tables::CJKKSC::EUCKR_ENCODE_PAGES)
  end

  # =======================================================================
  # CP949 (UHC — Microsoft EUC-KR superset)
  # =======================================================================

  def self.decode_cp949(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x81 && lead <= 0xFE
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x41 && trail <= 0xFE

    idx = (lead - Tables::CJKKSC::CP949_LEAD_MIN) * Tables::CJKKSC::CP949_TRAIL_COUNT + (trail - Tables::CJKKSC::CP949_TRAIL_MIN)
    cp = Tables::CJKKSC::CP949_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_cp949(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKKSC::CP949_ENCODE_SUMMARY,
      Tables::CJKKSC::CP949_ENCODE_PAGES)
  end

  # =======================================================================
  # JOHAB
  # =======================================================================

  def self.decode_johab(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    lead = b0.to_i32
    return DecodeResult::ILSEQ unless lead >= 0x84 && lead <= 0xF9
    return DecodeResult::TOOFEW if remaining < 2

    trail = src.unsafe_fetch(pos + 1).to_i32
    return DecodeResult::ILSEQ unless trail >= 0x31 && trail <= 0xFE

    idx = (lead - Tables::CJKKSC::JOHAB_LEAD_MIN) * Tables::CJKKSC::JOHAB_TRAIL_COUNT + (trail - Tables::CJKKSC::JOHAB_TRAIL_MIN)
    cp = Tables::CJKKSC::JOHAB_DECODE.unsafe_fetch(idx)
    cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
  end

  def self.encode_johab(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKKSC::JOHAB_ENCODE_SUMMARY,
      Tables::CJKKSC::JOHAB_ENCODE_PAGES)
  end

  # =======================================================================
  # EUC-TW (CNS 11643 plane 1 in EUC wrapper)
  # =======================================================================

  def self.decode_euc_tw(src : Bytes, pos : Int32) : DecodeResult
    remaining = src.size - pos
    return DecodeResult::TOOFEW if remaining < 1
    b0 = src.unsafe_fetch(pos)

    return DecodeResult.new(b0.to_u32, 1) if b0 < 0x80

    # Plane 1: lead 0xA1-0xFE, trail 0xA1-0xFE
    if b0 >= 0xA1_u8 && b0 <= 0xFE_u8
      return DecodeResult::TOOFEW if remaining < 2
      b1 = src.unsafe_fetch(pos + 1)
      return DecodeResult::ILSEQ unless b1 >= 0xA1_u8 && b1 <= 0xFE_u8

      idx = (b0.to_i32 - Tables::CJKEUCTW::EUCTW_LEAD_MIN) * Tables::CJKEUCTW::EUCTW_TRAIL_COUNT + (b1.to_i32 - Tables::CJKEUCTW::EUCTW_TRAIL_MIN)
      cp = Tables::CJKEUCTW::EUCTW_DECODE.unsafe_fetch(idx)
      return cp == 0xFFFF_u16 ? DecodeResult::ILSEQ : DecodeResult.new(cp.to_u32, 2)
    end

    # Multi-plane: 0x8E + plane indicator + lead + trail (4 bytes)
    # Plane 2+: 0x8E 0xA2-0xAF lead trail
    if b0 == 0x8E_u8
      return DecodeResult::TOOFEW if remaining < 4
      # We only have plane 1 in our tables; planes 2+ return ILSEQ for now
      return DecodeResult::ILSEQ
    end

    DecodeResult::ILSEQ
  end

  def self.encode_euc_tw(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    if cp < 0x80
      return EncodeResult::TOOSMALL if pos >= dst.size
      dst.to_unsafe[pos] = cp.to_u8
      return EncodeResult.new(1)
    end

    return EncodeResult::TOOSMALL if dst.size - pos < 2
    encode_2byte(cp, dst, pos,
      Tables::CJKEUCTW::EUCTW_ENCODE_SUMMARY,
      Tables::CJKEUCTW::EUCTW_ENCODE_PAGES)
  end

  # =======================================================================
  # GB2312 (alias for EUC-CN in our implementation)
  # =======================================================================

  def self.decode_gb2312(src : Bytes, pos : Int32) : DecodeResult
    decode_euc_cn(src, pos)
  end

  def self.encode_gb2312(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    encode_euc_cn(cp, dst, pos)
  end
end
