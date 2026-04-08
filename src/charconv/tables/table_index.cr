module CharConv::Tables
  # Indexed by EncodingID.value. Null for ASCII/UTF8/ISO_8859_1 (dedicated codecs).
  DECODE_TABLES = begin
    count = EncodingID.values.size
    arr = Array(Pointer(UInt16)).new(count, Pointer(UInt16).null)
    {% for enc in %w[
      ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
      ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
      ISO_8859_15 ISO_8859_16
      CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
      KOI8_R KOI8_U KOI8_RU
      MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
      MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
      CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
      CP864 CP865 CP866 CP869
      CP874 TIS_620 VISCII ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
      NEXTSTEP PT154 KOI8_T
      CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
      CP423 CP424 CP500 CP905 CP1026
      CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
      CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1
      TCVN
    ] %}
      arr[EncodingID::{{ enc.id }}.value] = SingleByte::{{ enc.id }}_DECODE.to_unsafe
    {% end %}
    arr
  end

  ENCODE_TABLES = begin
    count = EncodingID.values.size
    arr = Array(Pointer(UInt8)).new(count, Pointer(UInt8).null)
    {% for enc in %w[
      ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
      ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
      ISO_8859_15 ISO_8859_16
      CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
      KOI8_R KOI8_U KOI8_RU
      MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
      MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
      CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
      CP864 CP865 CP866 CP869
      CP874 TIS_620 VISCII ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
      NEXTSTEP PT154 KOI8_T
      CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
      CP423 CP424 CP500 CP905 CP1026
      CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
      CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1
      TCVN
    ] %}
      arr[EncodingID::{{ enc.id }}.value] = build_encode_table(SingleByte::{{ enc.id }}_DECODE, SingleByte::{{ enc.id }}_ENCODE_PAIRS)
    {% end %}
    arr
  end

  # Precomputed single-byte byte (0x80-0xFF) → packed UTF-8 tables.
  # Each entry: [len:8][b2:8][b1:8][b0:8] as UInt32. len=0 means undefined.
  SINGLEBYTE_TO_UTF8_TABLES = begin
    count = EncodingID.values.size
    arr = Array(Pointer(UInt32)).new(count, Pointer(UInt32).null)
    {% for enc in %w[
      ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
      ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
      ISO_8859_15 ISO_8859_16
      CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
      KOI8_R KOI8_U KOI8_RU
      MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
      MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
      CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
      CP864 CP865 CP866 CP869
      CP874 TIS_620 VISCII ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
      NEXTSTEP PT154 KOI8_T
      CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
      CP423 CP424 CP500 CP905 CP1026
      CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
      CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1
      TCVN
    ] %}
      arr[EncodingID::{{ enc.id }}.value] = build_sb_to_utf8_table(SingleByte::{{ enc.id }}_DECODE)
    {% end %}
    arr
  end

  private def self.build_sb_to_utf8_table(decode : StaticArray(UInt16, 256)) : Pointer(UInt32)
    table = Pointer(UInt32).malloc(128, 0_u32)
    128.times do |i|
      cp = decode[i + 128].to_u32
      next if cp == 0xFFFF_u32
      if cp < 0x80_u32
        table[i] = cp | (1_u32 << 24)
      elsif cp < 0x800_u32
        b0 = 0xC0_u32 | (cp >> 6)
        b1 = 0x80_u32 | (cp & 0x3F_u32)
        table[i] = b0 | (b1 << 8) | (2_u32 << 24)
      else
        b0 = 0xE0_u32 | (cp >> 12)
        b1 = 0x80_u32 | ((cp >> 6) & 0x3F_u32)
        b2 = 0x80_u32 | (cp & 0x3F_u32)
        table[i] = b0 | (b1 << 8) | (b2 << 16) | (3_u32 << 24)
      end
    end
    table
  end

  private def self.build_encode_table(decode : StaticArray(UInt16, 256), pairs : Array({UInt16, UInt8})) : Pointer(UInt8)
    table = Pointer(UInt8).malloc(65536, 0_u8)
    # Invert decode table: for each byte, set encode[codepoint] = byte
    (0..255).each do |b|
      cp = decode[b]
      table[cp] = b.to_u8 if cp != 0xFFFF_u16
    end
    # Apply system iconv encode preferences (overrides where different)
    pairs.each { |cp, byte| table[cp] = byte }
    table
  end
end
