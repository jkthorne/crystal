# Encoding name resolution and metadata registry.
#
# Maps 550+ encoding aliases (case-insensitive, punctuation-stripped) to
# `EncodingID` values, and stores `EncodingInfo` metadata (ASCII-superset flag,
# max bytes per character, statefulness) for each encoding.
#
# ```
# info = CharConv::Registry.lookup("UTF-8")       # => EncodingInfo
# info = CharConv::Registry.lookup("NONEXISTENT")  # => nil
# flags = CharConv::Registry.parse_flags("ASCII//TRANSLIT//IGNORE")
# ```
module CharConv::Registry
  # EncodingID → EncodingInfo flat array. Indexed by EncodingID.value.
  # Each entry: {ascii_superset, max_bytes_per_char, stateful}
  ENCODING_INFO = begin
    arr = Array(EncodingInfo).new(EncodingID.values.size) { |i|
      id = EncodingID.new(i.to_u16)
      EncodingInfo.new(id, false, 1_u8, false) # placeholder
    }

    # ASCII-superset single-byte (ascii_superset=true, max=1, stateful=false)
    {% for id in %w[ASCII UTF8 ISO_8859_1
                    ISO_8859_2 ISO_8859_3 ISO_8859_4 ISO_8859_5 ISO_8859_6 ISO_8859_7
                    ISO_8859_8 ISO_8859_9 ISO_8859_10 ISO_8859_11 ISO_8859_13 ISO_8859_14
                    ISO_8859_15 ISO_8859_16
                    CP1250 CP1251 CP1252 CP1253 CP1254 CP1255 CP1256 CP1257 CP1258
                    KOI8_R KOI8_U KOI8_RU
                    CP437 CP737 CP775 CP850 CP852 CP855 CP857 CP858 CP860 CP861 CP862 CP863
                    CP865 CP866 CP869
                    CP874 TIS_620 ARMSCII_8 GEORGIAN_ACADEMY GEORGIAN_PS HP_ROMAN8
                    NEXTSTEP PT154 KOI8_T
                    CP856 CP922 CP853 CP1046 CP1124 CP1125 CP1129 CP1131
                    CP1133 CP1161 CP1162 CP1163 ATARIST KZ_1048 MULELAO_1 RISCOS_LATIN1] %}
      arr[EncodingID::{{ id.id }}.value] = EncodingInfo.new(EncodingID::{{ id.id }}, true, 1_u8, false)
    {% end %}

    # UTF-8 needs max_bytes=4
    arr[EncodingID::UTF8.value] = EncodingInfo.new(EncodingID::UTF8, true, 4_u8, false)

    # Non-ASCII single-byte (ascii_superset=false, max=1, stateful=false)
    {% for id in %w[MAC_ROMAN MAC_CENTRAL_EUROPE MAC_ICELAND MAC_CROATIAN MAC_ROMANIA
                    MAC_CYRILLIC MAC_UKRAINE MAC_GREEK MAC_TURKISH MAC_HEBREW MAC_ARABIC MAC_THAI
                    CP864 VISCII
                    CP037 CP273 CP277 CP278 CP280 CP284 CP285 CP297
                    CP423 CP424 CP500 CP905 CP1026 TCVN] %}
      arr[EncodingID::{{ id.id }}.value] = EncodingInfo.new(EncodingID::{{ id.id }}, false, 1_u8, false)
    {% end %}

    # CJK stateless
    arr[EncodingID::EUC_JP.value]     = EncodingInfo.new(EncodingID::EUC_JP, true, 3_u8, false)
    arr[EncodingID::SHIFT_JIS.value]  = EncodingInfo.new(EncodingID::SHIFT_JIS, false, 2_u8, false)
    arr[EncodingID::CP932.value]      = EncodingInfo.new(EncodingID::CP932, false, 2_u8, false)
    arr[EncodingID::GBK.value]        = EncodingInfo.new(EncodingID::GBK, true, 2_u8, false)
    arr[EncodingID::GB2312.value]     = EncodingInfo.new(EncodingID::GB2312, true, 2_u8, false)
    arr[EncodingID::EUC_CN.value]     = EncodingInfo.new(EncodingID::EUC_CN, true, 2_u8, false)
    arr[EncodingID::GB18030.value]    = EncodingInfo.new(EncodingID::GB18030, true, 4_u8, false)
    arr[EncodingID::BIG5.value]       = EncodingInfo.new(EncodingID::BIG5, true, 2_u8, false)
    arr[EncodingID::CP950.value]      = EncodingInfo.new(EncodingID::CP950, true, 2_u8, false)
    arr[EncodingID::BIG5_HKSCS.value] = EncodingInfo.new(EncodingID::BIG5_HKSCS, true, 2_u8, false)
    arr[EncodingID::EUC_KR.value]     = EncodingInfo.new(EncodingID::EUC_KR, true, 2_u8, false)
    arr[EncodingID::CP949.value]      = EncodingInfo.new(EncodingID::CP949, true, 2_u8, false)
    arr[EncodingID::EUC_TW.value]     = EncodingInfo.new(EncodingID::EUC_TW, true, 4_u8, false)
    arr[EncodingID::JOHAB.value]      = EncodingInfo.new(EncodingID::JOHAB, true, 2_u8, false)

    # CJK stateful
    {% for id in %w[ISO2022_JP ISO2022_JP1 ISO2022_JP2 ISO2022_CN ISO2022_CN_EXT ISO2022_KR] %}
      arr[EncodingID::{{ id.id }}.value] = EncodingInfo.new(EncodingID::{{ id.id }}, false, 8_u8, true)
    {% end %}
    arr[EncodingID::HZ.value] = EncodingInfo.new(EncodingID::HZ, false, 4_u8, true)

    # Unicode family (none are ASCII supersets)
    {% for id in %w[UTF16_BE UTF16_LE UTF32_BE UTF32_LE] %}
      arr[EncodingID::{{ id.id }}.value] = EncodingInfo.new(EncodingID::{{ id.id }}, false, 4_u8, false)
    {% end %}
    arr[EncodingID::UTF16.value] = EncodingInfo.new(EncodingID::UTF16, false, 4_u8, true)
    arr[EncodingID::UTF32.value] = EncodingInfo.new(EncodingID::UTF32, false, 4_u8, true)

    arr[EncodingID::UCS2.value]          = EncodingInfo.new(EncodingID::UCS2, false, 2_u8, true)
    arr[EncodingID::UCS2_BE.value]       = EncodingInfo.new(EncodingID::UCS2_BE, false, 2_u8, false)
    arr[EncodingID::UCS2_LE.value]       = EncodingInfo.new(EncodingID::UCS2_LE, false, 2_u8, false)
    arr[EncodingID::UCS2_INTERNAL.value] = EncodingInfo.new(EncodingID::UCS2_INTERNAL, false, 2_u8, false)
    arr[EncodingID::UCS2_SWAPPED.value]  = EncodingInfo.new(EncodingID::UCS2_SWAPPED, false, 2_u8, false)

    arr[EncodingID::UCS4.value]          = EncodingInfo.new(EncodingID::UCS4, false, 4_u8, true)
    arr[EncodingID::UCS4_BE.value]       = EncodingInfo.new(EncodingID::UCS4_BE, false, 4_u8, false)
    arr[EncodingID::UCS4_LE.value]       = EncodingInfo.new(EncodingID::UCS4_LE, false, 4_u8, false)
    arr[EncodingID::UCS4_INTERNAL.value] = EncodingInfo.new(EncodingID::UCS4_INTERNAL, false, 4_u8, false)
    arr[EncodingID::UCS4_SWAPPED.value]  = EncodingInfo.new(EncodingID::UCS4_SWAPPED, false, 4_u8, false)

    arr[EncodingID::UTF7.value] = EncodingInfo.new(EncodingID::UTF7, false, 8_u8, true)
    arr[EncodingID::C99.value]  = EncodingInfo.new(EncodingID::C99, false, 10_u8, false)
    arr[EncodingID::JAVA.value] = EncodingInfo.new(EncodingID::JAVA, false, 12_u8, false)

    arr
  end

  # Normalized name → EncodingID (alias resolution)
  ALIASES = {
    # ASCII
    "ASCII"       => EncodingID::ASCII,
    "USASCII"     => EncodingID::ASCII,
    "ANSIX341968" => EncodingID::ASCII,
    "ISO646US"    => EncodingID::ASCII,
    "646"         => EncodingID::ASCII,
    "CHAR"        => EncodingID::ASCII,
    "CSASCII"     => EncodingID::ASCII,
    "ISOIR6"      => EncodingID::ASCII,
    "ISO6461991"  => EncodingID::ASCII,
    "IBM367"      => EncodingID::ASCII,
    "CP367"       => EncodingID::ASCII,

    # UTF-8
    "UTF8" => EncodingID::UTF8,

    # ISO-8859-1
    "ISO88591"     => EncodingID::ISO_8859_1,
    "LATIN1"       => EncodingID::ISO_8859_1,
    "ISO885911987" => EncodingID::ISO_8859_1,
    "CP819"        => EncodingID::ISO_8859_1,
    "IBM819"       => EncodingID::ISO_8859_1,
    "ISOIR100"     => EncodingID::ISO_8859_1,
    "L1"           => EncodingID::ISO_8859_1,
    "CSISOLATIN1"  => EncodingID::ISO_8859_1,

    # ISO-8859-2
    "ISO88592"     => EncodingID::ISO_8859_2,
    "LATIN2"       => EncodingID::ISO_8859_2,
    "ISO885921987" => EncodingID::ISO_8859_2,
    "ISOIR101"     => EncodingID::ISO_8859_2,
    "L2"           => EncodingID::ISO_8859_2,
    "CSISOLATIN2"  => EncodingID::ISO_8859_2,

    # ISO-8859-3
    "ISO88593"     => EncodingID::ISO_8859_3,
    "LATIN3"       => EncodingID::ISO_8859_3,
    "ISO885931988" => EncodingID::ISO_8859_3,
    "ISOIR109"     => EncodingID::ISO_8859_3,
    "L3"           => EncodingID::ISO_8859_3,
    "CSISOLATIN3"  => EncodingID::ISO_8859_3,

    # ISO-8859-4
    "ISO88594"     => EncodingID::ISO_8859_4,
    "LATIN4"       => EncodingID::ISO_8859_4,
    "ISO885941988" => EncodingID::ISO_8859_4,
    "ISOIR110"     => EncodingID::ISO_8859_4,
    "L4"           => EncodingID::ISO_8859_4,
    "CSISOLATIN4"  => EncodingID::ISO_8859_4,

    # ISO-8859-5
    "ISO88595"           => EncodingID::ISO_8859_5,
    "CYRILLIC"           => EncodingID::ISO_8859_5,
    "ISO885951988"       => EncodingID::ISO_8859_5,
    "ISOIR144"           => EncodingID::ISO_8859_5,
    "CSISOLATINCYRILLIC" => EncodingID::ISO_8859_5,

    # ISO-8859-6
    "ISO88596"           => EncodingID::ISO_8859_6,
    "ARABIC"             => EncodingID::ISO_8859_6,
    "ISO885961987"       => EncodingID::ISO_8859_6,
    "ISOIR127"           => EncodingID::ISO_8859_6,
    "ASMO708"            => EncodingID::ISO_8859_6,
    "ECMA114"            => EncodingID::ISO_8859_6,
    "CSISOLATINARABIC"   => EncodingID::ISO_8859_6,

    # ISO-8859-7
    "ISO88597"     => EncodingID::ISO_8859_7,
    "GREEK"        => EncodingID::ISO_8859_7,
    "GREEK8"       => EncodingID::ISO_8859_7,
    "ISO885972003" => EncodingID::ISO_8859_7,
    "ISO885971987" => EncodingID::ISO_8859_7,
    "ISOIR126"     => EncodingID::ISO_8859_7,
    "ECMA118"      => EncodingID::ISO_8859_7,
    "ELOT928"      => EncodingID::ISO_8859_7,

    # ISO-8859-8
    "ISO88598"     => EncodingID::ISO_8859_8,
    "HEBREW"       => EncodingID::ISO_8859_8,
    "ISO885981988" => EncodingID::ISO_8859_8,
    "ISOIR138"     => EncodingID::ISO_8859_8,

    # ISO-8859-9
    "ISO88599"     => EncodingID::ISO_8859_9,
    "LATIN5"       => EncodingID::ISO_8859_9,
    "ISO885991989" => EncodingID::ISO_8859_9,
    "ISOIR148"     => EncodingID::ISO_8859_9,
    "L5"           => EncodingID::ISO_8859_9,
    "CSISOLATIN5"  => EncodingID::ISO_8859_9,

    # ISO-8859-10
    "ISO885910"     => EncodingID::ISO_8859_10,
    "LATIN6"        => EncodingID::ISO_8859_10,
    "ISO8859101992" => EncodingID::ISO_8859_10,
    "ISOIR157"      => EncodingID::ISO_8859_10,

    # ISO-8859-11
    "ISO885911" => EncodingID::ISO_8859_11,

    # ISO-8859-13
    "ISO885913" => EncodingID::ISO_8859_13,
    "LATIN7"    => EncodingID::ISO_8859_13,
    "ISOIR179"  => EncodingID::ISO_8859_13,

    # ISO-8859-14
    "ISO885914"     => EncodingID::ISO_8859_14,
    "LATIN8"        => EncodingID::ISO_8859_14,
    "ISO8859141998" => EncodingID::ISO_8859_14,
    "ISOIR199"      => EncodingID::ISO_8859_14,
    "ISOCELTIC"     => EncodingID::ISO_8859_14,

    # ISO-8859-15
    "ISO885915"     => EncodingID::ISO_8859_15,
    "LATIN9"        => EncodingID::ISO_8859_15,
    "ISO8859151998" => EncodingID::ISO_8859_15,
    "ISOIR203"      => EncodingID::ISO_8859_15,

    # ISO-8859-16
    "ISO885916"     => EncodingID::ISO_8859_16,
    "LATIN10"       => EncodingID::ISO_8859_16,
    "ISO8859162001" => EncodingID::ISO_8859_16,
    "ISOIR226"      => EncodingID::ISO_8859_16,

    # Windows code pages
    "CP1250"       => EncodingID::CP1250,
    "WINDOWS1250"  => EncodingID::CP1250,
    "MSEE"         => EncodingID::CP1250,

    "CP1251"       => EncodingID::CP1251,
    "WINDOWS1251"  => EncodingID::CP1251,
    "MSCYRL"       => EncodingID::CP1251,

    "CP1252"       => EncodingID::CP1252,
    "WINDOWS1252"  => EncodingID::CP1252,
    "MSANSI"       => EncodingID::CP1252,

    "CP1253"       => EncodingID::CP1253,
    "WINDOWS1253"  => EncodingID::CP1253,
    "MSGREEK"      => EncodingID::CP1253,

    "CP1254"       => EncodingID::CP1254,
    "WINDOWS1254"  => EncodingID::CP1254,
    "MSTURK"       => EncodingID::CP1254,

    "CP1255"       => EncodingID::CP1255,
    "WINDOWS1255"  => EncodingID::CP1255,
    "MSHEBR"       => EncodingID::CP1255,

    "CP1256"       => EncodingID::CP1256,
    "WINDOWS1256"  => EncodingID::CP1256,
    "MSARAB"       => EncodingID::CP1256,

    "CP1257"       => EncodingID::CP1257,
    "WINDOWS1257"  => EncodingID::CP1257,
    "WINBALTRIM"   => EncodingID::CP1257,

    "CP1258"       => EncodingID::CP1258,
    "WINDOWS1258"  => EncodingID::CP1258,

    # KOI8
    "KOI8R"  => EncodingID::KOI8_R,
    "KOI8U"  => EncodingID::KOI8_U,
    "KOI8RU" => EncodingID::KOI8_RU,

    # Mac encodings
    "MACROMAN"          => EncodingID::MAC_ROMAN,
    "MACINTOSH"         => EncodingID::MAC_ROMAN,
    "MAC"               => EncodingID::MAC_ROMAN,
    "MACCENTRALEUROPE"  => EncodingID::MAC_CENTRAL_EUROPE,
    "MACICELAND"        => EncodingID::MAC_ICELAND,
    "MACCROATIAN"       => EncodingID::MAC_CROATIAN,
    "MACROMANIA"        => EncodingID::MAC_ROMANIA,
    "MACCYRILLIC"       => EncodingID::MAC_CYRILLIC,
    "MACUKRAINE"        => EncodingID::MAC_UKRAINE,
    "MACGREEK"          => EncodingID::MAC_GREEK,
    "MACTURKISH"        => EncodingID::MAC_TURKISH,
    "MACHEBREW"         => EncodingID::MAC_HEBREW,
    "MACARABIC"         => EncodingID::MAC_ARABIC,
    "MACTHAI"           => EncodingID::MAC_THAI,

    # DOS code pages
    "CP437"  => EncodingID::CP437,
    "IBM437" => EncodingID::CP437,
    "437"    => EncodingID::CP437,

    "CP737" => EncodingID::CP737,

    "CP775"  => EncodingID::CP775,
    "IBM775" => EncodingID::CP775,

    "CP850"  => EncodingID::CP850,
    "IBM850" => EncodingID::CP850,
    "850"    => EncodingID::CP850,

    "CP852"  => EncodingID::CP852,
    "IBM852" => EncodingID::CP852,
    "852"    => EncodingID::CP852,

    "CP855"  => EncodingID::CP855,
    "IBM855" => EncodingID::CP855,
    "855"    => EncodingID::CP855,

    "CP857"  => EncodingID::CP857,
    "IBM857" => EncodingID::CP857,
    "857"    => EncodingID::CP857,

    "CP858" => EncodingID::CP858,

    "CP860"  => EncodingID::CP860,
    "IBM860" => EncodingID::CP860,
    "860"    => EncodingID::CP860,

    "CP861"  => EncodingID::CP861,
    "IBM861" => EncodingID::CP861,
    "861"    => EncodingID::CP861,
    "CPIS"   => EncodingID::CP861,

    "CP862"  => EncodingID::CP862,
    "IBM862" => EncodingID::CP862,
    "862"    => EncodingID::CP862,

    "CP863"  => EncodingID::CP863,
    "IBM863" => EncodingID::CP863,
    "863"    => EncodingID::CP863,

    "CP864"  => EncodingID::CP864,
    "IBM864" => EncodingID::CP864,

    "CP865"  => EncodingID::CP865,
    "IBM865" => EncodingID::CP865,
    "865"    => EncodingID::CP865,

    "CP866"  => EncodingID::CP866,
    "IBM866" => EncodingID::CP866,
    "866"    => EncodingID::CP866,

    "CP869"  => EncodingID::CP869,
    "IBM869" => EncodingID::CP869,
    "869"    => EncodingID::CP869,
    "CPGR"   => EncodingID::CP869,

    # Other single-byte
    "CP874"      => EncodingID::CP874,
    "WINDOWS874" => EncodingID::CP874,

    "TIS620"       => EncodingID::TIS_620,
    "TIS6200"      => EncodingID::TIS_620,
    "TIS62025291"  => EncodingID::TIS_620,
    "TIS62025330"  => EncodingID::TIS_620,
    "TIS62025331"  => EncodingID::TIS_620,
    "ISOIR166"     => EncodingID::TIS_620,

    "VISCII"    => EncodingID::VISCII,
    "VISCII111" => EncodingID::VISCII,

    "ARMSCII8" => EncodingID::ARMSCII_8,

    "GEORGIANACADEMY" => EncodingID::GEORGIAN_ACADEMY,
    "GEORGIANPS"      => EncodingID::GEORGIAN_PS,

    "HPROMAN8" => EncodingID::HP_ROMAN8,
    "ROMAN8"   => EncodingID::HP_ROMAN8,
    "R8"       => EncodingID::HP_ROMAN8,

    "NEXTSTEP" => EncodingID::NEXTSTEP,

    "PT154"    => EncodingID::PT154,
    "CP154"    => EncodingID::PT154,
    "PTCP154"  => EncodingID::PT154,

    "KOI8T" => EncodingID::KOI8_T,

    # Unicode family
    "UTF16BE" => EncodingID::UTF16_BE,
    "UTF16LE" => EncodingID::UTF16_LE,
    "UTF16"   => EncodingID::UTF16,

    "UTF32BE" => EncodingID::UTF32_BE,
    "UTF32LE" => EncodingID::UTF32_LE,
    "UTF32"   => EncodingID::UTF32,

    "UCS2"          => EncodingID::UCS2,
    "ISO10646UCS2"  => EncodingID::UCS2,
    "CSUNICODE"     => EncodingID::UCS2,
    "UCS2BE"        => EncodingID::UCS2_BE,
    "UNICODE11"     => EncodingID::UCS2_BE,
    "UNICODEBIG"    => EncodingID::UCS2_BE,
    "CSUNICODE11"   => EncodingID::UCS2_BE,
    "UCS2LE"        => EncodingID::UCS2_LE,
    "UNICODELITTLE" => EncodingID::UCS2_LE,
    "UCS2INTERNAL"  => EncodingID::UCS2_INTERNAL,
    "UCS2SWAPPED"   => EncodingID::UCS2_SWAPPED,

    "UCS4"          => EncodingID::UCS4,
    "ISO10646UCS4"  => EncodingID::UCS4,
    "CSUCS4"        => EncodingID::UCS4,
    "UCS4BE"        => EncodingID::UCS4_BE,
    "UCS4LE"        => EncodingID::UCS4_LE,
    "UCS4INTERNAL"  => EncodingID::UCS4_INTERNAL,
    "UCS4SWAPPED"   => EncodingID::UCS4_SWAPPED,

    "UTF7"            => EncodingID::UTF7,
    "UNICODE11UTF7"   => EncodingID::UTF7,
    "CSUNICODE11UTF7" => EncodingID::UTF7,

    "C99"  => EncodingID::C99,
    "JAVA" => EncodingID::JAVA,

    # EBCDIC
    "CP037"       => EncodingID::CP037,
    "IBM037"      => EncodingID::CP037,
    "EBCDICCP037" => EncodingID::CP037,

    "CP273"  => EncodingID::CP273,
    "IBM273" => EncodingID::CP273,

    "CP277"  => EncodingID::CP277,
    "IBM277" => EncodingID::CP277,

    "CP278"  => EncodingID::CP278,
    "IBM278" => EncodingID::CP278,

    "CP280"  => EncodingID::CP280,
    "IBM280" => EncodingID::CP280,

    "CP284"  => EncodingID::CP284,
    "IBM284" => EncodingID::CP284,

    "CP285"  => EncodingID::CP285,
    "IBM285" => EncodingID::CP285,

    "CP297"  => EncodingID::CP297,
    "IBM297" => EncodingID::CP297,

    "CP423"  => EncodingID::CP423,
    "IBM423" => EncodingID::CP423,

    "CP424"  => EncodingID::CP424,
    "IBM424" => EncodingID::CP424,

    "CP500"       => EncodingID::CP500,
    "IBM500"      => EncodingID::CP500,
    "EBCDICCP500" => EncodingID::CP500,

    "CP905"  => EncodingID::CP905,
    "IBM905" => EncodingID::CP905,

    "CP1026"  => EncodingID::CP1026,
    "IBM1026" => EncodingID::CP1026,

    # Remaining ASCII-superset single-byte
    "CP856"  => EncodingID::CP856,
    "IBM856" => EncodingID::CP856,

    "CP922"  => EncodingID::CP922,
    "IBM922" => EncodingID::CP922,

    "CP853"  => EncodingID::CP853,

    "CP1046" => EncodingID::CP1046,

    "CP1124" => EncodingID::CP1124,

    "CP1125" => EncodingID::CP1125,

    "CP1129" => EncodingID::CP1129,

    "CP1131" => EncodingID::CP1131,

    "CP1133" => EncodingID::CP1133,

    "CP1161" => EncodingID::CP1161,

    "CP1162" => EncodingID::CP1162,

    "CP1163" => EncodingID::CP1163,

    "ATARIST" => EncodingID::ATARIST,

    "KZ1048"       => EncodingID::KZ_1048,
    "STRK10482002" => EncodingID::KZ_1048,
    "RK1048"       => EncodingID::KZ_1048,

    "MULELAO1" => EncodingID::MULELAO_1,

    "RISCOSLATIN1" => EncodingID::RISCOS_LATIN1,

    # Non-ASCII non-EBCDIC
    "TCVN"      => EncodingID::TCVN,
    "TCVN5712"  => EncodingID::TCVN,
    "TCVN57121" => EncodingID::TCVN,

    # CJK — Japanese
    "EUCJP"                                  => EncodingID::EUC_JP,
    "EXTENDEDUNIXCODEPACKEDFORMATFORJAPANESE" => EncodingID::EUC_JP,
    "CSEUCPKDFMTJAPANESE"                    => EncodingID::EUC_JP,

    "SHIFTJIS"     => EncodingID::SHIFT_JIS,
    "SJIS"         => EncodingID::SHIFT_JIS,
    "MSKANJI"      => EncodingID::SHIFT_JIS,
    "CSSHIFTJIS"   => EncodingID::SHIFT_JIS,

    "CP932"        => EncodingID::CP932,
    "WINDOWS31J"   => EncodingID::CP932,

    "ISO2022JP"    => EncodingID::ISO2022_JP,
    "CSISO2022JP"  => EncodingID::ISO2022_JP,
    "ISO2022JP1"   => EncodingID::ISO2022_JP1,
    "ISO2022JP2"   => EncodingID::ISO2022_JP2,
    "CSISO2022JP2" => EncodingID::ISO2022_JP2,

    # CJK — Chinese (Simplified)
    "GB2312"          => EncodingID::GB2312,
    "CSGB2312"        => EncodingID::GB2312,
    "GB231280"        => EncodingID::GB2312,
    "CHINESE"         => EncodingID::GB2312,
    "ISOIR58"         => EncodingID::GB2312,
    "CSISO58GB231280" => EncodingID::GB2312,

    "GBK"          => EncodingID::GBK,
    "CP936"        => EncodingID::GBK,
    "MS936"        => EncodingID::GBK,
    "WINDOWS936"   => EncodingID::GBK,

    "GB18030"      => EncodingID::GB18030,

    "EUCCN"        => EncodingID::EUC_CN,
    "CNGB"         => EncodingID::EUC_CN,

    "HZ"           => EncodingID::HZ,
    "HZGB2312"     => EncodingID::HZ,

    "ISO2022CN"    => EncodingID::ISO2022_CN,
    "CSISO2022CN"  => EncodingID::ISO2022_CN,
    "ISO2022CNEXT" => EncodingID::ISO2022_CN_EXT,

    # CJK — Chinese (Traditional)
    "BIG5"         => EncodingID::BIG5,
    "BIGFIVE"      => EncodingID::BIG5,
    "CNBIG5"       => EncodingID::BIG5,
    "CSBIG5"       => EncodingID::BIG5,

    "CP950"        => EncodingID::CP950,
    "WINDOWS950"   => EncodingID::CP950,

    "BIG5HKSCS"    => EncodingID::BIG5_HKSCS,

    "EUCTW"        => EncodingID::EUC_TW,
    "CSEUCTW"      => EncodingID::EUC_TW,

    # CJK — Korean
    "EUCKR"        => EncodingID::EUC_KR,
    "CSEUCKR"      => EncodingID::EUC_KR,

    "CP949"        => EncodingID::CP949,
    "UHC"          => EncodingID::CP949,

    "ISO2022KR"    => EncodingID::ISO2022_KR,
    "CSISO2022KR"  => EncodingID::ISO2022_KR,

    "JOHAB"        => EncodingID::JOHAB,
    "CP1361"       => EncodingID::JOHAB,
  }

  CANONICAL_NAMES = [
    "ASCII", "UTF-8", "ISO-8859-1",
    "ISO-8859-2", "ISO-8859-3", "ISO-8859-4", "ISO-8859-5", "ISO-8859-6",
    "ISO-8859-7", "ISO-8859-8", "ISO-8859-9", "ISO-8859-10", "ISO-8859-11",
    "ISO-8859-13", "ISO-8859-14", "ISO-8859-15", "ISO-8859-16",
    "CP1250", "CP1251", "CP1252", "CP1253", "CP1254", "CP1255", "CP1256", "CP1257", "CP1258",
    "KOI8-R", "KOI8-U", "KOI8-RU",
    "MacRoman", "MacCentralEurope", "MacIceland", "MacCroatian", "MacRomania",
    "MacCyrillic", "MacUkraine", "MacGreek", "MacTurkish", "MacHebrew", "MacArabic", "MacThai",
    "CP437", "CP737", "CP775", "CP850", "CP852", "CP855", "CP857", "CP858",
    "CP860", "CP861", "CP862", "CP863", "CP864", "CP865", "CP866", "CP869",
    "CP874", "TIS-620", "VISCII", "ARMSCII-8",
    "Georgian-Academy", "Georgian-PS", "HP-Roman8", "NEXTSTEP", "PT154", "KOI8-T",
    # Unicode family
    "UTF-16BE", "UTF-16LE", "UTF-16",
    "UTF-32BE", "UTF-32LE", "UTF-32",
    "UCS-2", "UCS-2BE", "UCS-2LE", "UCS-2-INTERNAL", "UCS-2-SWAPPED",
    "UCS-4", "UCS-4BE", "UCS-4LE", "UCS-4-INTERNAL", "UCS-4-SWAPPED",
    "UTF-7", "C99", "JAVA",
    # Remaining single-byte
    "CP037", "CP273", "CP277", "CP278", "CP280", "CP284", "CP285", "CP297",
    "CP423", "CP424", "CP500", "CP905", "CP1026",
    "CP856", "CP922", "CP853", "CP1046", "CP1124", "CP1125", "CP1129", "CP1131",
    "CP1133", "CP1161", "CP1162", "CP1163", "ATARIST", "KZ-1048", "MULELAO-1",
    "RISCOS-LATIN1", "TCVN",
    # CJK
    "EUC-JP", "Shift_JIS", "CP932",
    "ISO-2022-JP", "ISO-2022-JP-1", "ISO-2022-JP-2",
    "GB2312", "GBK", "GB18030", "EUC-CN", "HZ",
    "ISO-2022-CN", "ISO-2022-CN-EXT",
    "Big5", "CP950", "Big5-HKSCS", "EUC-TW",
    "EUC-KR", "CP949", "ISO-2022-KR", "JOHAB",
  ]

  # Normalizes an encoding name by uppercasing and stripping non-alphanumeric
  # characters. For example, `"UTF-8"` → `"UTF8"`, `"ISO-8859-1"` → `"ISO88591"`.
  def self.normalize(name : String) : String
    String.build(name.size) do |io|
      name.each_char do |c|
        if c.ascii_alphanumeric?
          io << c.upcase
        end
      end
    end
  end

  # Looks up an encoding by name, returning its `EncodingInfo` or `nil`.
  #
  # Strips `//IGNORE` and `//TRANSLIT` suffixes before lookup. Accepts any
  # alias registered in `ALIASES` (case-insensitive, punctuation-stripped).
  def self.lookup(name : String) : EncodingInfo?
    # Strip //IGNORE and //TRANSLIT suffixes
    clean = name
    if idx = clean.index("//")
      clean = clean[0...idx]
    end
    normalized = normalize(clean)
    if id = ALIASES[normalized]?
      ENCODING_INFO[id.value]
    end
  end

  # Extracts `ConversionFlags` from `//IGNORE` and `//TRANSLIT` suffixes
  # in an encoding name string.
  def self.parse_flags(name : String) : ConversionFlags
    flags = ConversionFlags::None
    if idx = name.index("//")
      suffix = name[idx..].upcase
      flags |= ConversionFlags::Translit if suffix.includes?("TRANSLIT")
      flags |= ConversionFlags::Ignore if suffix.includes?("IGNORE")
    end
    flags
  end

  # Returns a copy of the canonical encoding name list.
  def self.canonical_names : Array(String)
    CANONICAL_NAMES.dup
  end
end
