# Converts text between character encodings using a Unicode (UCS-4) pivot.
#
# Every conversion goes through: `Source bytes → UCS-4 codepoint → Target bytes`.
# For ASCII-superset pairs, an 8-byte word scanner identifies ASCII runs and
# copies them directly at memory bandwidth.
#
# ### Basic usage
#
# ```
# converter = CharConv::Converter.new("EUC-JP", "UTF-8")
# consumed, written = converter.convert(input_bytes, output_bytes)
# ```
#
# ### Error handling with status codes
#
# ```
# converter = CharConv::Converter.new("UTF-8", "ISO-8859-1")
# consumed, written, status = converter.convert_with_status(src, dst)
#
# case status
# when .ok?     then output.write(dst[0, written])
# when .e2_big? then # grow output buffer, retry with src[consumed..]
# when .eilseq? then # invalid byte at src[consumed]
# when .einval? then # incomplete sequence, wait for more input
# end
# ```
#
# ### Stateful encodings
#
# Encodings like ISO-2022-JP, UTF-7, and HZ maintain internal state across
# calls. After processing a complete document, call `#flush_encoder` to emit
# any pending escape sequences. Call `#reset` before reusing the converter
# for a new, independent document.
#
# ### Thread safety
#
# `Converter` is **NOT** thread-safe — it holds mutable codec state. Do not
# share across fibers or threads. Call `#dup` to create an independent copy.
#
# ```
# converter = CharConv::Converter.new("ISO-2022-JP", "UTF-8")
# spawn { converter.dup.convert(data1, out1) }
# spawn { converter.dup.convert(data2, out2) }
# ```
class CharConv::Converter
  getter from : EncodingInfo
  getter to : EncodingInfo
  getter flags : ConversionFlags
  @decode_table : Pointer(UInt16)
  @encode_table : Pointer(UInt8)
  @sb_to_utf8_table : Pointer(UInt32)

  # Creates a new converter from *from_encoding* to *to_encoding*.
  #
  # Encoding names are case-insensitive and support 550+ aliases (e.g.
  # `"UTF-8"`, `"utf8"`, `"CP65001"` all resolve to UTF-8). Append
  # `//TRANSLIT` and/or `//IGNORE` to the target encoding for flag control.
  #
  # Raises `ArgumentError` if either encoding name is unknown.
  #
  # ```
  # converter = CharConv::Converter.new("Shift_JIS", "UTF-8")
  # converter = CharConv::Converter.new("UTF-8", "ASCII//TRANSLIT//IGNORE")
  # ```
  def initialize(from_encoding : String, to_encoding : String)
    @from = Registry.lookup(from_encoding) || raise ArgumentError.new("Unknown encoding: #{from_encoding}")
    @to = Registry.lookup(to_encoding) || raise ArgumentError.new("Unknown encoding: #{to_encoding}")
    @flags = Registry.parse_flags(to_encoding)
    @state_decode = CodecState.new
    @state_encode = CodecState.new
    @decode_table = Tables::DECODE_TABLES[@from.id.value]
    @encode_table = Tables::ENCODE_TABLES[@to.id.value]
    @sb_to_utf8_table = Tables::SINGLEBYTE_TO_UTF8_TABLES[@from.id.value]
    init_codec_modes
  end

  private def init_codec_modes
    @state_decode.mode, @state_decode.flags = codec_mode_for(@from.id)
    @state_encode.mode, @state_encode.flags = codec_mode_for(@to.id)
  end

  private def codec_mode_for(id : EncodingID) : {UInt8, UInt8}
    case id
    when .utf16_be?, .ucs2_be?  then {1_u8, 0_u8}
    when .utf16_le?, .ucs2_le?  then {2_u8, 0_u8}
    when .utf32_be?, .ucs4_be?  then {1_u8, 0_u8}
    when .utf32_le?, .ucs4_le?  then {2_u8, 0_u8}
    when .ucs2_internal?, .ucs4_internal?
      {% if flag?(:little_endian) %}
        {2_u8, 0_u8}
      {% else %}
        {1_u8, 0_u8}
      {% end %}
    when .ucs2_swapped?, .ucs4_swapped?
      {% if flag?(:little_endian) %}
        {1_u8, 0_u8} # BE (swapped from native LE)
      {% else %}
        {2_u8, 0_u8} # LE (swapped from native BE)
      {% end %}
    when .utf16?, .utf32?, .ucs2?, .ucs4?
      {0_u8, 0_u8} # BOM detection / will emit BOM
    when .utf7?
      {1_u8, 0_u8} # direct mode
    when .hz?, .iso2022_jp?, .iso2022_jp1?, .iso2022_jp2?,
         .iso2022_cn?, .iso2022_cn_ext?, .iso2022_kr?
      {0_u8, 0_u8} # ASCII mode
    else
      {1_u8, 0_u8} # default
    end
  end

  # Consume BOM from decode source. Returns bytes to skip.
  private def consume_decode_bom(src : Bytes) : Int32
    case @from.id
    when .utf16?, .ucs2?
      return 0 if src.size < 2
      if src.unsafe_fetch(0) == 0xFE_u8 && src.unsafe_fetch(1) == 0xFF_u8
        @state_decode.mode = 1_u8 # BE
        return 2
      elsif src.unsafe_fetch(0) == 0xFF_u8 && src.unsafe_fetch(1) == 0xFE_u8
        @state_decode.mode = 2_u8 # LE
        return 2
      else
        @state_decode.mode = 1_u8 # default BE
        return 0
      end
    when .utf32?, .ucs4?
      return 0 if src.size < 4
      if src.unsafe_fetch(0) == 0x00_u8 && src.unsafe_fetch(1) == 0x00_u8 &&
         src.unsafe_fetch(2) == 0xFE_u8 && src.unsafe_fetch(3) == 0xFF_u8
        @state_decode.mode = 1_u8 # BE
        return 4
      elsif src.unsafe_fetch(0) == 0xFF_u8 && src.unsafe_fetch(1) == 0xFE_u8 &&
            src.unsafe_fetch(2) == 0x00_u8 && src.unsafe_fetch(3) == 0x00_u8
        @state_decode.mode = 2_u8 # LE
        return 4
      else
        @state_decode.mode = 1_u8 # default BE
        return 0
      end
    else
      @state_decode.mode = 1_u8
      return 0
    end
  end

  # Emit BOM to encode output. Returns bytes written.
  private def emit_encode_bom(dst : Bytes) : Int32
    case @to.id
    when .utf16?, .ucs2?
      return 0 if dst.size < 2
      # Emit BE BOM (FE FF) and set mode to BE
      dst.to_unsafe[0] = 0xFE_u8
      dst.to_unsafe[1] = 0xFF_u8
      @state_encode.mode = 1_u8 # BE
      return 2
    when .utf32?, .ucs4?
      return 0 if dst.size < 4
      # Emit BE BOM (00 00 FE FF) and set mode to BE
      dst.to_unsafe[0] = 0x00_u8
      dst.to_unsafe[1] = 0x00_u8
      dst.to_unsafe[2] = 0xFE_u8
      dst.to_unsafe[3] = 0xFF_u8
      @state_encode.mode = 1_u8 # BE
      return 4
    else
      @state_encode.mode = 1_u8
      return 0
    end
  end

  # Scans a run of ASCII bytes using 8-byte word reads.
  # Note: the UInt64 load may be unaligned since Bytes doesn't guarantee
  # 8-byte alignment. This is safe on x86-64 and ARM64 (our target platforms).
  @[AlwaysInline]
  private def scan_ascii_run(src : Bytes, from : Int32) : Int32
    pos = from
    remaining = src.size - pos

    while remaining >= 8
      word = (src.to_unsafe + pos).as(Pointer(UInt64)).value
      break if word & 0x8080808080808080_u64 != 0
      pos += 8
      remaining -= 8
    end

    while pos < src.size
      break if src.unsafe_fetch(pos) >= 0x80_u8
      pos += 1
    end

    pos - from
  end

  @[AlwaysInline]
  private def decode_one(src : Bytes, pos : Int32) : DecodeResult
    case @from.id
    when .ascii?      then Decode.ascii(src, pos)
    when .utf8?       then Decode.utf8(src, pos)
    when .iso_8859_1? then Decode.iso_8859_1(src, pos)
    when .utf16_be?   then Codec::UTF16.decode_be(src, pos)
    when .utf16_le?   then Codec::UTF16.decode_le(src, pos)
    when .utf16?
      @state_decode.mode == 2_u8 ? Codec::UTF16.decode_le(src, pos) : Codec::UTF16.decode_be(src, pos)
    when .utf32_be?   then Codec::UTF32.decode_be(src, pos)
    when .utf32_le?   then Codec::UTF32.decode_le(src, pos)
    when .utf32?
      @state_decode.mode == 2_u8 ? Codec::UTF32.decode_le(src, pos) : Codec::UTF32.decode_be(src, pos)
    when .ucs2_be?
      Codec::UTF16.decode_ucs2_be(src, pos)
    when .ucs2_le?
      Codec::UTF16.decode_ucs2_le(src, pos)
    when .ucs2?
      @state_decode.mode == 2_u8 ? Codec::UTF16.decode_ucs2_le(src, pos) : Codec::UTF16.decode_ucs2_be(src, pos)
    when .ucs2_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF16.decode_ucs2_le(src, pos)
      {% else %}
        Codec::UTF16.decode_ucs2_be(src, pos)
      {% end %}
    when .ucs2_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF16.decode_ucs2_be(src, pos)
      {% else %}
        Codec::UTF16.decode_ucs2_le(src, pos)
      {% end %}
    when .ucs4_be?    then Codec::UTF32.decode_be(src, pos)
    when .ucs4_le?    then Codec::UTF32.decode_le(src, pos)
    when .ucs4?
      @state_decode.mode == 2_u8 ? Codec::UTF32.decode_le(src, pos) : Codec::UTF32.decode_be(src, pos)
    when .ucs4_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF32.decode_le(src, pos)
      {% else %}
        Codec::UTF32.decode_be(src, pos)
      {% end %}
    when .ucs4_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF32.decode_be(src, pos)
      {% else %}
        Codec::UTF32.decode_le(src, pos)
      {% end %}
    when .utf7?
      Codec::UTF7.decode(src, pos, pointerof(@state_decode))
    when .c99?  then Codec::C99.decode(src, pos)
    when .java? then Codec::Java.decode(src, pos)
    # CJK stateless
    when .euc_jp?      then Codec::CJK.decode_euc_jp(src, pos)
    when .shift_jis?   then Codec::CJK.decode_shift_jis(src, pos)
    when .cp932?       then Codec::CJK.decode_cp932(src, pos)
    when .gbk?         then Codec::CJK.decode_gbk(src, pos)
    when .euc_cn?, .gb2312? then Codec::CJK.decode_euc_cn(src, pos)
    when .big5?        then Codec::CJK.decode_big5(src, pos)
    when .cp950?       then Codec::CJK.decode_cp950(src, pos)
    when .big5_hkscs?  then Codec::CJK.decode_big5_hkscs(src, pos)
    when .euc_kr?      then Codec::CJK.decode_euc_kr(src, pos)
    when .cp949?       then Codec::CJK.decode_cp949(src, pos)
    when .johab?       then Codec::CJK.decode_johab(src, pos)
    when .euc_tw?      then Codec::CJK.decode_euc_tw(src, pos)
    when .gb18030?     then Codec::GB18030.decode(src, pos)
    # CJK stateful
    when .iso2022_jp?, .iso2022_jp1?, .iso2022_jp2?
      Codec::ISO2022JP.decode(src, pos, pointerof(@state_decode))
    when .iso2022_cn?, .iso2022_cn_ext?
      Codec::ISO2022CN.decode(src, pos, pointerof(@state_decode))
    when .iso2022_kr?
      Codec::ISO2022KR.decode(src, pos, pointerof(@state_decode))
    when .hz?
      Codec::HZ.decode(src, pos, pointerof(@state_decode))
    else Decode.single_byte_table(src, pos, @decode_table)
    end
  end

  @[AlwaysInline]
  private def encode_one(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    case @to.id
    when .ascii?      then Encode.ascii(cp, dst, pos)
    when .utf8?       then Encode.utf8(cp, dst, pos)
    when .iso_8859_1? then Encode.iso_8859_1(cp, dst, pos)
    when .utf16_be?   then Codec::UTF16.encode_be(cp, dst, pos)
    when .utf16_le?   then Codec::UTF16.encode_le(cp, dst, pos)
    when .utf16?
      @state_encode.mode == 2_u8 ? Codec::UTF16.encode_le(cp, dst, pos) : Codec::UTF16.encode_be(cp, dst, pos)
    when .utf32_be?   then Codec::UTF32.encode_be(cp, dst, pos)
    when .utf32_le?   then Codec::UTF32.encode_le(cp, dst, pos)
    when .utf32?
      @state_encode.mode == 2_u8 ? Codec::UTF32.encode_le(cp, dst, pos) : Codec::UTF32.encode_be(cp, dst, pos)
    when .ucs2_be?
      Codec::UTF16.encode_ucs2_be(cp, dst, pos)
    when .ucs2_le?
      Codec::UTF16.encode_ucs2_le(cp, dst, pos)
    when .ucs2?
      @state_encode.mode == 2_u8 ? Codec::UTF16.encode_ucs2_le(cp, dst, pos) : Codec::UTF16.encode_ucs2_be(cp, dst, pos)
    when .ucs2_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF16.encode_ucs2_le(cp, dst, pos)
      {% else %}
        Codec::UTF16.encode_ucs2_be(cp, dst, pos)
      {% end %}
    when .ucs2_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF16.encode_ucs2_be(cp, dst, pos)
      {% else %}
        Codec::UTF16.encode_ucs2_le(cp, dst, pos)
      {% end %}
    when .ucs4_be?    then Codec::UTF32.encode_be(cp, dst, pos)
    when .ucs4_le?    then Codec::UTF32.encode_le(cp, dst, pos)
    when .ucs4?
      @state_encode.mode == 2_u8 ? Codec::UTF32.encode_le(cp, dst, pos) : Codec::UTF32.encode_be(cp, dst, pos)
    when .ucs4_internal?
      {% if flag?(:little_endian) %}
        Codec::UTF32.encode_le(cp, dst, pos)
      {% else %}
        Codec::UTF32.encode_be(cp, dst, pos)
      {% end %}
    when .ucs4_swapped?
      {% if flag?(:little_endian) %}
        Codec::UTF32.encode_be(cp, dst, pos)
      {% else %}
        Codec::UTF32.encode_le(cp, dst, pos)
      {% end %}
    when .utf7?
      Codec::UTF7.encode(cp, dst, pos, pointerof(@state_encode))
    when .c99?  then Codec::C99.encode(cp, dst, pos)
    when .java? then Codec::Java.encode(cp, dst, pos)
    # CJK stateless
    when .euc_jp?      then Codec::CJK.encode_euc_jp(cp, dst, pos)
    when .shift_jis?   then Codec::CJK.encode_shift_jis(cp, dst, pos)
    when .cp932?       then Codec::CJK.encode_cp932(cp, dst, pos)
    when .gbk?         then Codec::CJK.encode_gbk(cp, dst, pos)
    when .euc_cn?, .gb2312? then Codec::CJK.encode_euc_cn(cp, dst, pos)
    when .big5?        then Codec::CJK.encode_big5(cp, dst, pos)
    when .cp950?       then Codec::CJK.encode_cp950(cp, dst, pos)
    when .big5_hkscs?  then Codec::CJK.encode_big5_hkscs(cp, dst, pos)
    when .euc_kr?      then Codec::CJK.encode_euc_kr(cp, dst, pos)
    when .cp949?       then Codec::CJK.encode_cp949(cp, dst, pos)
    when .johab?       then Codec::CJK.encode_johab(cp, dst, pos)
    when .euc_tw?      then Codec::CJK.encode_euc_tw(cp, dst, pos)
    when .gb18030?     then Codec::GB18030.encode(cp, dst, pos)
    # CJK stateful
    when .iso2022_jp?, .iso2022_jp1?, .iso2022_jp2?
      Codec::ISO2022JP.encode(cp, dst, pos, pointerof(@state_encode))
    when .iso2022_cn?, .iso2022_cn_ext?
      Codec::ISO2022CN.encode(cp, dst, pos, pointerof(@state_encode))
    when .iso2022_kr?
      Codec::ISO2022KR.encode(cp, dst, pos, pointerof(@state_encode))
    when .hz?
      Codec::HZ.encode(cp, dst, pos, pointerof(@state_encode))
    else Encode.single_byte_table(cp, dst, pos, @encode_table)
    end
  end

  # Try to transliterate a codepoint that can't be encoded directly.
  # Returns number of bytes written to dst, or 0 on failure.
  private def transliterate(cp : UInt32, dst : Bytes, dst_pos : Int32) : Int32
    replacement = Transliteration.lookup(cp)
    return 0 unless replacement
    total = 0
    replacement.each do |rcp|
      break if rcp == 0
      er = encode_one(rcp, dst, dst_pos + total)
      return 0 if er.status <= 0 # any failure → whole transliteration fails
      total += er.status
    end
    total
  end

  # Handle a decode error. Returns src bytes to skip (for IGNORE), or nil to stop.
  private def handle_decode_error(status : Int32) : Int32?
    if status == -1 # ILSEQ
      return 1 if @flags.ignore?
    end
    nil # ILSEQ without IGNORE, or TOOFEW — stop
  end

  # Fast path for conversions where both encodings are ASCII supersets.
  private def convert_ascii_fast(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      dr = decode_one(src, src_pos)
      if dr.status <= 0
        skip = handle_decode_error(dr.status)
        if skip
          src_pos += skip
          next
        end
        status = dr.status == 0 ? ConvertStatus::EINVAL : ConvertStatus::EILSEQ
        return {src_pos, dst_pos, status}
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1 # ILUNI
        if @flags.translit?
          t = transliterate(dr.codepoint, dst, dst_pos)
          if t > 0
            src_pos += dr.status
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += dr.status
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      elsif er.status == 0 # TOOSMALL
        return {src_pos, dst_pos, ConvertStatus::E2BIG}
      else
        src_pos += dr.status
        dst_pos += er.status
      end
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # General character-at-a-time loop for non-ASCII-superset encodings.
  private def convert_general(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    # BOM handling — only for UTF-16/32 family (mode 0 = BOM detection needed)
    if @state_decode.mode == 0_u8 && (@from.id.utf16? || @from.id.utf32? || @from.id.ucs2? || @from.id.ucs4?)
      src_pos = consume_decode_bom(src)
    end
    if @state_encode.mode == 0_u8 && (@to.id.utf16? || @to.id.utf32? || @to.id.ucs2? || @to.id.ucs4?)
      dst_pos = emit_encode_bom(dst)
    end

    while src_pos < src.size
      dr = decode_one(src, src_pos)
      if dr.status <= 0
        skip = handle_decode_error(dr.status)
        if skip
          src_pos += skip
          next
        end
        status = dr.status == 0 ? ConvertStatus::EINVAL : ConvertStatus::EILSEQ
        return {src_pos, dst_pos, status}
      end

      # Stateful codecs return codepoint 0 with status > 0 for escape sequences
      # (mode switches that consume bytes but produce no character).
      # Only skip for stateful encodings — stateless codecs decoding to U+0000 is a real NUL.
      if dr.codepoint == 0 && dr.status > 0 && @from.stateful
        src_pos += dr.status
        next
      end

      er = encode_one(dr.codepoint, dst, dst_pos)
      if er.status == -1 # ILUNI
        if @flags.translit?
          t = transliterate(dr.codepoint, dst, dst_pos)
          if t > 0
            src_pos += dr.status
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += dr.status
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      elsif er.status == 0 # TOOSMALL
        return {src_pos, dst_pos, ConvertStatus::E2BIG}
      else
        src_pos += dr.status
        dst_pos += er.status
      end
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # Converts bytes from *src* into *dst*, returning `{src_consumed, dst_written}`.
  #
  # You provide both buffers — no allocations occur. Call repeatedly in a loop
  # for streaming conversion, advancing *src* by `consumed` and *dst* by `written`
  # after each call.
  #
  # ```
  # converter = CharConv::Converter.new("EUC-JP", "UTF-8")
  # consumed, written = converter.convert(input_bytes, output_bytes)
  # ```
  def convert(src : Bytes, dst : Bytes) : {Int32, Int32}
    consumed, written, _status = convert_with_status(src, dst)
    {consumed, written}
  end

  # Converts bytes from *src* into *dst*, returning `{src_consumed, dst_written, status}`.
  #
  # The `ConvertStatus` indicates why conversion stopped:
  # - `OK` — all input consumed successfully
  # - `E2BIG` — output buffer full; consume written bytes, then call again
  # - `EILSEQ` — invalid byte sequence at `src[consumed]`
  # - `EINVAL` — incomplete multibyte sequence at end of input; provide more bytes
  #
  # ### Buffer sizing
  #
  # For output, allocate at least `src.size * to.max_bytes_per_char` bytes to
  # avoid `E2BIG` on the first call. For unknown input, start with `src.size * 4`
  # (covers worst-case UTF-8 expansion) and grow on `E2BIG`.
  #
  # ```
  # converter = CharConv::Converter.new("UTF-8", "UTF-16BE")
  # src = input_bytes
  # dst = Bytes.new(src.size * 4)
  # consumed, written, status = converter.convert_with_status(src, dst)
  # ```
  def convert_with_status(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    if @from.id.iso_8859_1? && @to.id.utf8?
      convert_iso8859_1_to_utf8(src, dst)
    elsif @from.id.utf8? && @to.id.iso_8859_1?
      convert_utf8_to_iso8859_1(src, dst)
    elsif @to.id.utf8? && @from.ascii_superset && @from.max_bytes_per_char == 1 && !@sb_to_utf8_table.null?
      convert_singlebyte_to_utf8(src, dst)
    elsif @from.id.utf8? && @to.ascii_superset && @to.max_bytes_per_char == 1 && !@encode_table.null?
      convert_utf8_to_singlebyte(src, dst)
    elsif @from.id.utf8? && (@to.id.euc_jp? || @to.id.gbk? || @to.id.euc_cn? || @to.id.gb2312? || @to.id.euc_kr?)
      convert_utf8_to_cjk(src, dst)
    elsif @from.id.utf8? && @to.id.utf8?
      convert_utf8_to_utf8(src, dst)
    elsif @from.ascii_superset && @to.ascii_superset
      convert_ascii_fast(src, dst)
    else
      convert_general(src, dst)
    end
  end

  # Maximum output buffer size for one-shot conversion (64 MB).
  ONE_SHOT_MAX_BYTES = 64 * 1024 * 1024

  # Converts *input* bytes and returns the result as a new `Bytes` slice.
  #
  # Automatically allocates and grows the output buffer as needed (starting at
  # `input.size * 2`, doubling on `E2BIG`). Stateful encoders are flushed
  # automatically. Raises `ConversionError` if:
  # - The output would exceed 64 MB
  # - An invalid/incomplete sequence is encountered (unless `//IGNORE` is set)
  #
  # ```
  # converter = CharConv::Converter.new("GBK", "UTF-8")
  # utf8_bytes = converter.convert(gbk_input)
  # ```
  def convert(input : Bytes) : Bytes
    buf_size = Math.max(input.size.to_i64 * 2, 64_i64)
    # For BOM-detecting encodings, ensure room for BOM
    buf_size += 4 if @to.id.utf16? || @to.id.utf32? || @to.id.ucs2? || @to.id.ucs4?

    loop do
      capped = Math.min(buf_size, ONE_SHOT_MAX_BYTES.to_i64).to_i32
      dst = Bytes.new(capped)
      reset
      src_consumed, dst_written, status = convert_with_status(input, dst)

      if status == ConvertStatus::E2BIG
        if buf_size >= ONE_SHOT_MAX_BYTES
          raise CharConv::ConversionError.new(
            "Output exceeds #{ONE_SHOT_MAX_BYTES} byte limit at byte #{src_consumed} " \
            "(#{src_consumed}/#{input.size} bytes consumed)"
          )
        end
        buf_size = buf_size * 2
        next
      end

      # Flush stateful encoders (ISO-2022-JP, UTF-7, HZ, etc.)
      flush_written = flush_encoder(dst, dst_written)
      if flush_written == 0 || dst_written + flush_written <= dst.size
        dst_written += flush_written
      else
        # Flush didn't fit — grow and retry
        buf_size = buf_size * 2
        next if buf_size <= ONE_SHOT_MAX_BYTES
        raise CharConv::ConversionError.new("Output exceeds #{ONE_SHOT_MAX_BYTES} byte limit during flush")
      end

      if src_consumed < input.size
        unless @flags.ignore?
          raise CharConv::ConversionError.new(
            "Conversion failed at byte #{src_consumed} (#{src_consumed}/#{input.size} bytes consumed)"
          )
        end
        # With //IGNORE, trailing incomplete sequences are silently discarded
      end
      return dst[0, dst_written]
    end
  end

  # Reads from *input* IO, converts, and writes to *output* IO.
  #
  # Processes data in chunks of *buffer_size* bytes. The output buffer is
  # automatically sized to `buffer_size * max_bytes_per_char` for the target
  # encoding. Stateful encoders are flushed at EOF.
  #
  # Raises `ConversionError` if unconsumed bytes remain at EOF (unless `//IGNORE`).
  #
  # ```
  # converter = CharConv::Converter.new("GB18030", "UTF-8")
  # converter.convert(input_io, output_io, buffer_size: 16384)
  # ```
  def convert(input : IO, output : IO, buffer_size : Int32 = 8192)
    src_buf = Bytes.new(buffer_size)
    dst_buf = Bytes.new(buffer_size * @to.max_bytes_per_char.to_i32)
    src_len = 0

    loop do
      bytes_read = input.read(src_buf[src_len..])
      src_len += bytes_read
      at_eof = bytes_read == 0

      break if src_len == 0 && at_eof

      src = src_buf[0, src_len]
      consumed, written = convert(src, dst_buf)
      output.write(dst_buf[0, written]) if written > 0

      remaining = src_len - consumed
      if remaining > 0
        if at_eof
          # Unconsumed bytes at EOF — incomplete sequence
          unless @flags.ignore?
            raise CharConv::ConversionError.new(
              "Incomplete sequence at end of input (#{remaining} byte(s) remaining)"
            )
          end
          break
        end
        (src_buf.to_unsafe + consumed).copy_to(src_buf.to_unsafe, remaining) if consumed > 0
      end
      src_len = remaining

      break if at_eof
    end

    # Flush stateful encoders
    flush_written = flush_encoder(dst_buf, 0)
    output.write(dst_buf[0, flush_written]) if flush_written > 0
  end

  # Flushes any pending state from stateful encoders (ISO-2022-JP, UTF-7, HZ, etc.)
  # into *dst* starting at byte offset *pos*. Returns the number of bytes written.
  #
  # Call this after the last `convert` call when processing a complete document.
  # For stateless encodings, this is a no-op returning 0.
  #
  # ```
  # converter = CharConv::Converter.new("UTF-8", "ISO-2022-JP")
  # consumed, written = converter.convert(src, dst)
  # flush_len = converter.flush_encoder(dst, written)
  # total_written = written + flush_len
  # ```
  def flush_encoder(dst : Bytes, pos : Int32) : Int32
    if @to.id.utf7? && @state_encode.mode == 2_u8
      Codec::UTF7.flush_base64(dst, pos, pointerof(@state_encode))
    elsif @to.id.iso2022_jp? || @to.id.iso2022_jp1? || @to.id.iso2022_jp2?
      Codec::ISO2022JP.flush(dst, pos, pointerof(@state_encode))
    elsif @to.id.iso2022_cn? || @to.id.iso2022_cn_ext?
      Codec::ISO2022CN.flush(dst, pos, pointerof(@state_encode))
    elsif @to.id.iso2022_kr?
      Codec::ISO2022KR.flush(dst, pos, pointerof(@state_encode))
    elsif @to.id.hz?
      Codec::HZ.flush(dst, pos, pointerof(@state_encode))
    else
      0
    end
  end

  # Resets the converter to its initial state.
  #
  # Call this before reusing a converter for a new, independent document.
  # Required for stateful encodings (ISO-2022-JP, UTF-7, HZ, etc.) that
  # accumulate mode state across `convert` calls.
  def reset
    @state_decode.reset
    @state_encode.reset
    init_codec_modes
  end

  # Creates an independent copy with fresh codec state.
  #
  # The new instance shares immutable table pointers but has its own state,
  # making it safe to use in a separate fiber. Always `dup` *before* starting
  # a conversion — mid-stream state is **not** copied.
  #
  # ```
  # base = CharConv::Converter.new("ISO-2022-JP", "UTF-8")
  # spawn { base.dup.convert(data, output) }
  # ```
  def dup : Converter
    conv = Converter.allocate
    conv.initialize_dup(@from, @to, @flags, @decode_table, @encode_table, @sb_to_utf8_table)
    conv
  end

  # :nodoc:
  protected def initialize_dup(@from : EncodingInfo, @to : EncodingInfo, @flags : ConversionFlags,
                               @decode_table : Pointer(UInt16), @encode_table : Pointer(UInt8),
                               @sb_to_utf8_table : Pointer(UInt32))
    @state_decode = CodecState.new
    @state_encode = CodecState.new
    init_codec_modes
  end

  # UTF-8 → UTF-8 fast path: validates and copies directly, no decode-pivot-encode.
  # Reuses scan_ascii_run + memcpy for ASCII runs; validates multi-byte sequences inline.
  private def convert_utf8_to_utf8(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      # Fast ASCII scan + memcpy
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      # Non-ASCII: validate UTF-8 sequence and copy directly
      b0 = src.unsafe_fetch(src_pos).to_u32
      remaining = src.size - src_pos

      if b0 < 0xC2 || b0 > 0xF4
        # Invalid lead byte (0x80-0xBF continuations, 0xC0-0xC1 overlong, > 0xF4)
        if @flags.ignore?
          src_pos += 1
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 < 0xE0
        # 2-byte sequence
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if remaining < 2
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        unless b1 & 0xC0 == 0x80
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        seq_len = 2
      elsif b0 < 0xF0
        # 3-byte sequence
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if remaining < 3
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        if cp < 0x0800 || (cp >= 0xD800 && cp <= 0xDFFF)
          if @flags.ignore?
            src_pos += 3
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        seq_len = 3
      else
        # 4-byte sequence
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if remaining < 4
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        b3 = src.unsafe_fetch(src_pos + 3).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80) && (b3 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        if cp < 0x10000 || cp > 0x10FFFF
          if @flags.ignore?
            src_pos += 4
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        seq_len = 4
      end

      # Copy validated sequence
      return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst.size - dst_pos < seq_len
      (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, seq_len)
      src_pos += seq_len
      dst_pos += seq_len
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # ISO-8859-1 → UTF-8 fast path: pure bit math, no tables needed.
  # Every byte 0x80-0xFF maps to U+0080-U+00FF → 2-byte UTF-8.
  private def convert_iso8859_1_to_utf8(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      # Batch non-ASCII: all bytes 0x80-0xFF → 2-byte UTF-8 via bit math
      while src_pos < src.size
        byte = src.unsafe_fetch(src_pos)
        break if byte < 0x80_u8
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst.size - dst_pos < 2
        ptr = dst.to_unsafe + dst_pos
        ptr[0] = (0xC0_u8 | (byte >> 6))
        ptr[1] = (0x80_u8 | (byte & 0x3F_u8))
        src_pos += 1
        dst_pos += 2
      end
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # UTF-8 → ISO-8859-1 fast path: only U+0000-U+00FF are representable.
  private def convert_utf8_to_iso8859_1(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst_pos >= dst.size

      b0 = src.unsafe_fetch(src_pos).to_u32

      if b0 < 0xC2
        if @flags.ignore?
          src_pos += 1
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 < 0xE0 # 2-byte UTF-8 → U+0080..U+07FF
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 2
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        unless b1 & 0xC0 == 0x80
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
        if cp <= 0xFF
          dst.to_unsafe[dst_pos] = cp.to_u8
          src_pos += 2
          dst_pos += 1
          next
        end
        # cp > 0xFF: not representable
        if @flags.translit?
          t = transliterate(cp, dst, dst_pos)
          if t > 0
            src_pos += 2
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += 2
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      # 3-byte and 4-byte: decode fully for TRANSLIT support, never directly representable
      if b0 < 0xF0
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 3
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        if cp < 0x0800 || (cp >= 0xD800 && cp <= 0xDFFF)
          if @flags.ignore?
            src_pos += 3
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        if @flags.translit?
          t = transliterate(cp, dst, dst_pos)
          if t > 0
            src_pos += 3
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += 3
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 <= 0xF4
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 4
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        b3 = src.unsafe_fetch(src_pos + 3).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80) && (b3 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        if @flags.translit?
          t = transliterate(cp, dst, dst_pos)
          if t > 0
            src_pos += 4
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += 4
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if @flags.ignore?
        src_pos += 1
        next
      end
      return {src_pos, dst_pos, ConvertStatus::EILSEQ}
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # Generic single-byte ASCII-superset → UTF-8 fast path.
  # Uses precomputed packed UTF-8 table, batches consecutive non-ASCII bytes.
  private def convert_singlebyte_to_utf8(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    table = @sb_to_utf8_table
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      # Batch non-ASCII bytes: tight inner loop avoids re-entering ASCII scanner
      while src_pos < src.size
        byte = src.unsafe_fetch(src_pos)
        break if byte < 0x80_u8

        packed = table[byte.to_i32 - 128]
        len = (packed >> 24).to_i32

        if len == 0
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end

        return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst.size - dst_pos < len

        ptr = dst.to_unsafe + dst_pos
        ptr[0] = (packed & 0xFF).to_u8
        ptr[1] = ((packed >> 8) & 0xFF).to_u8 if len >= 2
        ptr[2] = ((packed >> 16) & 0xFF).to_u8 if len >= 3

        src_pos += 1
        dst_pos += len
      end
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # Generic UTF-8 → single-byte ASCII-superset fast path.
  # Inline UTF-8 decode + direct 64KB encode table lookup.
  private def convert_utf8_to_singlebyte(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    enc_table = @encode_table
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst_pos >= dst.size

      b0 = src.unsafe_fetch(src_pos).to_u32

      if b0 < 0xC2
        if @flags.ignore?
          src_pos += 1
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 < 0xE0 # 2-byte UTF-8
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 2
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        unless b1 & 0xC0 == 0x80
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
        byte = enc_table[cp]
        if byte != 0 || cp == 0
          dst.to_unsafe[dst_pos] = byte
          src_pos += 2
          dst_pos += 1
          next
        end
        if @flags.translit?
          t = transliterate(cp, dst, dst_pos)
          if t > 0
            src_pos += 2
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += 2
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 < 0xF0 # 3-byte UTF-8
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 3
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        if cp < 0x0800 || (cp >= 0xD800 && cp <= 0xDFFF)
          if @flags.ignore?
            src_pos += 3
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        byte = enc_table[cp]
        if byte != 0
          dst.to_unsafe[dst_pos] = byte
          src_pos += 3
          dst_pos += 1
          next
        end
        if @flags.translit?
          t = transliterate(cp, dst, dst_pos)
          if t > 0
            src_pos += 3
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += 3
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 <= 0xF4 # 4-byte UTF-8 → never representable in single-byte
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 4
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        b3 = src.unsafe_fetch(src_pos + 3).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80) && (b3 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        if @flags.translit?
          t = transliterate(cp, dst, dst_pos)
          if t > 0
            src_pos += 4
            dst_pos += t
            next
          end
        end
        if @flags.ignore?
          src_pos += 4
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if @flags.ignore?
        src_pos += 1
        next
      end
      return {src_pos, dst_pos, ConvertStatus::EILSEQ}
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end

  # UTF-8 → CJK (EUC-JP, GBK, EUC-CN, EUC-KR) fast path.
  # Inline UTF-8 decode + direct 2-level page table encode, with ASCII scan + memcpy.
  private def convert_utf8_to_cjk(src : Bytes, dst : Bytes) : {Int32, Int32, ConvertStatus}
    # Select encoding-specific tables
    case @to.id
    when .euc_jp?
      summary = Tables::CJKJis::EUCJP_ENCODE_SUMMARY
      pages = Tables::CJKJis::EUCJP_ENCODE_PAGES
    when .gbk?
      summary = Tables::CJKGB::GBK_ENCODE_SUMMARY
      pages = Tables::CJKGB::GBK_ENCODE_PAGES
    when .euc_cn?, .gb2312?
      summary = Tables::CJKGB::EUCCN_ENCODE_SUMMARY
      pages = Tables::CJKGB::EUCCN_ENCODE_PAGES
    when .euc_kr?
      summary = Tables::CJKKSC::EUCKR_ENCODE_SUMMARY
      pages = Tables::CJKKSC::EUCKR_ENCODE_PAGES
    else
      return convert_ascii_fast(src, dst)
    end

    is_euc_jp = @to.id.euc_jp?
    src_pos = 0
    dst_pos = 0

    while src_pos < src.size
      # Fast ASCII scan + memcpy
      ascii_len = scan_ascii_run(src, src_pos)
      if ascii_len > 0
        avail = dst.size - dst_pos
        copy_len = Math.min(ascii_len, avail)
        (src.to_unsafe + src_pos).copy_to(dst.to_unsafe + dst_pos, copy_len)
        src_pos += copy_len
        dst_pos += copy_len
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if copy_len < ascii_len
        next
      end

      b0 = src.unsafe_fetch(src_pos).to_u32

      if b0 < 0xC2
        if @flags.ignore?
          src_pos += 1
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      if b0 < 0xE0 # 2-byte UTF-8 → U+0080..U+07FF
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 2
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        unless b1 & 0xC0 == 0x80
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x1F) << 6) | (b1 & 0x3F)
        seq_len = 2
      elsif b0 < 0xF0 # 3-byte UTF-8 → U+0800..U+FFFF
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 3
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F)
        if cp < 0x0800 || (cp >= 0xD800 && cp <= 0xDFFF)
          if @flags.ignore?
            src_pos += 3
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        seq_len = 3
      elsif b0 <= 0xF4 # 4-byte UTF-8 → U+10000..U+10FFFF
        return {src_pos, dst_pos, ConvertStatus::EINVAL} if src.size - src_pos < 4
        b1 = src.unsafe_fetch(src_pos + 1).to_u32
        b2 = src.unsafe_fetch(src_pos + 2).to_u32
        b3 = src.unsafe_fetch(src_pos + 3).to_u32
        unless (b1 & 0xC0 == 0x80) && (b2 & 0xC0 == 0x80) && (b3 & 0xC0 == 0x80)
          if @flags.ignore?
            src_pos += 1
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        cp = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
        if cp < 0x10000 || cp > 0x10FFFF
          if @flags.ignore?
            src_pos += 4
            next
          end
          return {src_pos, dst_pos, ConvertStatus::EILSEQ}
        end
        seq_len = 4
      else
        if @flags.ignore?
          src_pos += 1
          next
        end
        return {src_pos, dst_pos, ConvertStatus::EILSEQ}
      end

      # EUC-JP special case: half-width katakana U+FF61..U+FF9F → 0x8E + byte
      if is_euc_jp && cp >= 0xFF61 && cp <= 0xFF9F
        return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst.size - dst_pos < 2
        dst.to_unsafe[dst_pos] = 0x8E_u8
        dst.to_unsafe[dst_pos + 1] = (0xA1_u32 + cp - 0xFF61_u32).to_u8
        src_pos += seq_len
        dst_pos += 2
        next
      end

      # 2-level page table encode
      if cp <= 0xFFFF
        high = (cp >> 8).to_i32 & 0xFF
        page_idx = summary.unsafe_fetch(high)
        if page_idx != 0xFFFF_u16
          encoded = pages[page_idx.to_i32].unsafe_fetch(cp.to_i32 & 0xFF)
          if encoded != 0_u16
            return {src_pos, dst_pos, ConvertStatus::E2BIG} if dst.size - dst_pos < 2
            dst.to_unsafe[dst_pos] = (encoded >> 8).to_u8
            dst.to_unsafe[dst_pos + 1] = (encoded & 0xFF).to_u8
            src_pos += seq_len
            dst_pos += 2
            next
          end
        end
      end

      # Codepoint not encodable — try TRANSLIT/IGNORE
      if @flags.translit?
        t = transliterate(cp, dst, dst_pos)
        if t > 0
          src_pos += seq_len
          dst_pos += t
          next
        end
      end
      if @flags.ignore?
        src_pos += seq_len
        next
      end
      return {src_pos, dst_pos, ConvertStatus::EILSEQ}
    end

    {src_pos, dst_pos, ConvertStatus::OK}
  end
end
