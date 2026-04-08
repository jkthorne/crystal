module CharConv
  # Stack-allocated result from decoding one source character to a Unicode codepoint.
  #
  # Check `#status` to determine the outcome:
  # - `status > 0` — success: *status* bytes were consumed from the source, `#codepoint` holds the decoded value
  # - `status == 0` — incomplete sequence: need more input bytes
  # - `status == -1` — illegal byte sequence
  #
  # Use `#ok?` as a shorthand for `status > 0`.
  struct DecodeResult
    getter codepoint : UInt32
    getter status : Int32

    def initialize(@codepoint : UInt32, @status : Int32)
    end

    # Sentinel: illegal byte sequence in source.
    ILSEQ  = new(0_u32, -1)
    # Sentinel: incomplete multibyte sequence (need more input).
    TOOFEW = new(0_u32, 0)

    # Returns `true` if decoding succeeded (consumed at least one byte).
    @[AlwaysInline]
    def ok? : Bool
      @status > 0
    end
  end

  # Stack-allocated result from encoding one Unicode codepoint to target bytes.
  #
  # Check `#status` to determine the outcome:
  # - `status > 0` — success: *status* bytes were written to the destination
  # - `status == 0` — output buffer too small
  # - `status == -1` — codepoint not representable in the target encoding
  #
  # Use `#ok?` as a shorthand for `status > 0`.
  struct EncodeResult
    getter status : Int32

    def initialize(@status : Int32)
    end

    # Sentinel: codepoint not representable in target encoding.
    ILUNI    = new(-1)
    # Sentinel: output buffer too small for the encoded bytes.
    TOOSMALL = new(0)

    # Returns `true` if encoding succeeded (wrote at least one byte).
    @[AlwaysInline]
    def ok? : Bool
      @status > 0
    end
  end

  # Identifies a specific character encoding. 189 values covering ASCII, Unicode,
  # ISO-8859, Windows codepages, Mac, DOS/IBM, EBCDIC, CJK, and more.
  enum EncodingID : UInt16
    ASCII
    UTF8
    ISO_8859_1
    ISO_8859_2
    ISO_8859_3
    ISO_8859_4
    ISO_8859_5
    ISO_8859_6
    ISO_8859_7
    ISO_8859_8
    ISO_8859_9
    ISO_8859_10
    ISO_8859_11
    ISO_8859_13
    ISO_8859_14
    ISO_8859_15
    ISO_8859_16
    CP1250
    CP1251
    CP1252
    CP1253
    CP1254
    CP1255
    CP1256
    CP1257
    CP1258
    KOI8_R
    KOI8_U
    KOI8_RU
    MAC_ROMAN
    MAC_CENTRAL_EUROPE
    MAC_ICELAND
    MAC_CROATIAN
    MAC_ROMANIA
    MAC_CYRILLIC
    MAC_UKRAINE
    MAC_GREEK
    MAC_TURKISH
    MAC_HEBREW
    MAC_ARABIC
    MAC_THAI
    CP437
    CP737
    CP775
    CP850
    CP852
    CP855
    CP857
    CP858
    CP860
    CP861
    CP862
    CP863
    CP864
    CP865
    CP866
    CP869
    CP874
    TIS_620
    VISCII
    ARMSCII_8
    GEORGIAN_ACADEMY
    GEORGIAN_PS
    HP_ROMAN8
    NEXTSTEP
    PT154
    KOI8_T
    # Phase 3: Unicode family encodings
    UTF16_BE
    UTF16_LE
    UTF16
    UTF32_BE
    UTF32_LE
    UTF32
    UCS2
    UCS2_BE
    UCS2_LE
    UCS2_INTERNAL
    UCS2_SWAPPED
    UCS4
    UCS4_BE
    UCS4_LE
    UCS4_INTERNAL
    UCS4_SWAPPED
    UTF7
    C99
    JAVA
    # Phase 5: Remaining single-byte encodings
    # EBCDIC (NOT ASCII supersets)
    CP037
    CP273
    CP277
    CP278
    CP280
    CP284
    CP285
    CP297
    CP423
    CP424
    CP500
    CP905
    CP1026
    # ASCII-superset single-byte
    CP856
    CP922
    CP853
    CP1046
    CP1124
    CP1125
    CP1129
    CP1131
    CP1133
    CP1161
    CP1162
    CP1163
    ATARIST
    KZ_1048
    MULELAO_1
    RISCOS_LATIN1
    # Non-ASCII non-EBCDIC
    TCVN
    # Phase 4: CJK encodings
    # Japanese
    EUC_JP
    SHIFT_JIS
    CP932
    ISO2022_JP
    ISO2022_JP1
    ISO2022_JP2
    # Chinese (Simplified)
    GB2312
    GBK
    GB18030
    EUC_CN
    HZ
    ISO2022_CN
    ISO2022_CN_EXT
    # Chinese (Traditional)
    BIG5
    CP950
    BIG5_HKSCS
    EUC_TW
    # Korean
    EUC_KR
    CP949
    ISO2022_KR
    JOHAB
  end

  # Metadata about a character encoding: whether it's an ASCII superset,
  # maximum bytes per character, and whether it requires stateful codec state.
  struct EncodingInfo
    getter id : EncodingID
    getter ascii_superset : Bool
    getter max_bytes_per_char : UInt8
    getter stateful : Bool

    def initialize(@id : EncodingID, @ascii_superset : Bool, @max_bytes_per_char : UInt8, @stateful : Bool)
    end
  end

  # Status code returned by `Converter#convert_with_status`, indicating why
  # conversion stopped. Modeled after GNU iconv errno values.
  #
  # ```
  # consumed, written, status = converter.convert_with_status(src, dst)
  # case status
  # when .ok?     then puts "done"
  # when .e2_big? then puts "output buffer full — call again"
  # when .eilseq? then puts "invalid byte at position #{consumed}"
  # when .einval? then puts "incomplete sequence — need more input"
  # end
  # ```
  enum ConvertStatus
    # All input was consumed successfully.
    OK
    # Output buffer is full. Consume the written bytes and call again
    # with the remaining input and a fresh (or emptied) output buffer.
    E2BIG
    # An invalid byte sequence was encountered at the current source position.
    # The `consumed` return value indicates the byte offset of the error.
    EILSEQ
    # The input ends with an incomplete multibyte sequence. Provide more
    # input bytes to complete the sequence, or treat as an error at EOF.
    EINVAL
  end

  # Flags controlling conversion behavior, parsed from `//IGNORE` and
  # `//TRANSLIT` suffixes on the target encoding name.
  #
  # ```
  # # Parsed automatically from encoding name:
  # converter = CharConv::Converter.new("UTF-8", "ASCII//TRANSLIT//IGNORE")
  # converter.flags.translit? # => true
  # converter.flags.ignore?   # => true
  # ```
  @[Flags]
  enum ConversionFlags : UInt8
    # Skip invalid input bytes and unencodable characters instead of stopping.
    Ignore   = 1
    # Attempt transliteration (e.g. `"é"` → `"e"`) before giving up on unencodable characters.
    Translit = 2
  end

  # Per-codec mutable state for stateful encodings (ISO-2022-JP, UTF-7, HZ, etc.).
  # Tracks the current encoding mode, internal buffer for multi-byte assembly,
  # and codec-specific flags.
  struct CodecState
    property mode : UInt8
    property flags : UInt8
    property buffer : UInt32
    property count : UInt8

    def initialize
      @mode = 0_u8
      @flags = 0_u8
      @buffer = 0_u32
      @count = 0_u8
    end

    def reset
      @mode = 0_u8
      @flags = 0_u8
      @buffer = 0_u32
      @count = 0_u8
    end
  end
end
