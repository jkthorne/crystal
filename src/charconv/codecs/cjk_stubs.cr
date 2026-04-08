# Stub implementations for CJK codecs when building with -Dcharconv_minimal.
# All methods return ILSEQ/ILUNI — CJK encodings are not supported in minimal builds.

module CharConv::Codec::CJK
  {% for name in %w[euc_jp shift_jis cp932 gbk euc_cn big5 cp950 big5_hkscs euc_kr cp949 johab euc_tw gb2312] %}
    def self.decode_{{name.id}}(src : Bytes, pos : Int32) : DecodeResult
      DecodeResult::ILSEQ
    end

    def self.encode_{{name.id}}(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
      EncodeResult::ILUNI
    end
  {% end %}
end

module CharConv::Codec::GB18030
  def self.decode(src : Bytes, pos : Int32) : DecodeResult
    DecodeResult::ILSEQ
  end

  def self.encode(cp : UInt32, dst : Bytes, pos : Int32) : EncodeResult
    EncodeResult::ILUNI
  end
end

{% for mod in %w[ISO2022JP ISO2022CN ISO2022KR HZ] %}
  module CharConv::Codec::{{mod.id}}
    def self.decode(src : Bytes, pos : Int32, state : Pointer(CodecState)) : DecodeResult
      DecodeResult::ILSEQ
    end

    def self.encode(cp : UInt32, dst : Bytes, pos : Int32, state : Pointer(CodecState)) : EncodeResult
      EncodeResult::ILUNI
    end

    def self.flush(dst : Bytes, pos : Int32, state : Pointer(CodecState)) : Int32
      0
    end
  end
{% end %}
