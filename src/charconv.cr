require "./charconv/types"
require "./charconv/decode"
require "./charconv/encode"
require "./charconv/tables/single_byte"
require "./charconv/tables/table_index"
require "./charconv/codecs/utf16"
require "./charconv/codecs/utf32"
require "./charconv/codecs/utf7"
require "./charconv/codecs/c99"
{% if flag?(:charconv_minimal) %}
  require "./charconv/codecs/cjk_stubs"
{% else %}
  require "./charconv/tables/cjk_jis"
  require "./charconv/tables/cjk_gb"
  require "./charconv/tables/cjk_big5"
  require "./charconv/tables/cjk_ksc"
  require "./charconv/tables/cjk_euctw"
  require "./charconv/tables/gb18030_ranges"
  require "./charconv/codecs/cjk"
  require "./charconv/codecs/gb18030"
  require "./charconv/codecs/iso2022_jp"
  require "./charconv/codecs/iso2022_cn"
  require "./charconv/codecs/iso2022_kr"
  require "./charconv/codecs/hz"
{% end %}
require "./charconv/registry"
require "./charconv/transliteration"
require "./charconv/converter"

# Pure Crystal implementation of GNU libiconv. Converts text between 150+
# character encodings using Unicode (UCS-4) as a pivot.
#
# ### One-shot conversion
#
# ```
# result = CharConv.convert("Hello", "UTF-8", "ISO-8859-1")
# result = CharConv.convert(input_bytes, "Shift_JIS", "UTF-8")
# ```
#
# ### Streaming conversion
#
# ```
# converter = CharConv::Converter.new("EUC-JP", "UTF-8")
# consumed, written = converter.convert(input_bytes, output_bytes)
# ```
#
# ### Flags
#
# Append `//TRANSLIT` to transliterate unencodable characters, or `//IGNORE`
# to silently skip them:
#
# ```
# CharConv.convert(input, "UTF-8", "ASCII//TRANSLIT")
# CharConv.convert(input, "UTF-8", "ASCII//IGNORE")
# ```
module CharConv
  VERSION = "0.1.0"

  # Raised when a one-shot conversion fails.
  #
  # This occurs when:
  # - An invalid byte sequence is encountered and `//IGNORE` is not set
  # - An incomplete multibyte sequence is found at the end of input
  # - The output would exceed the 64 MB safety limit
  class ConversionError < Exception
  end

  # Converts *input* bytes from encoding *from* to encoding *to*.
  #
  # Returns the converted output as `Bytes`. Raises `ConversionError` on failure.
  #
  # ```
  # utf8 = CharConv.convert(latin1_bytes, "ISO-8859-1", "UTF-8")
  # ```
  def self.convert(input : Bytes, from : String, to : String) : Bytes
    converter = Converter.new(from, to)
    converter.convert(input)
  end

  # Converts a *input* string from encoding *from* to encoding *to*.
  #
  # Returns the converted output as `Bytes`. Raises `ConversionError` on failure.
  #
  # ```
  # result = CharConv.convert("café", "UTF-8", "ISO-8859-1")
  # ```
  def self.convert(input : String, from : String, to : String) : Bytes
    convert(input.to_slice, from, to)
  end

  # Reads from *input* IO, converts from encoding *from* to *to*, and writes to *output* IO.
  #
  # Processes data in chunks of *buffer_size* bytes (default 8192). Raises `ConversionError`
  # if an incomplete sequence remains at EOF (unless `//IGNORE` is set).
  #
  # ```
  # File.open("input.txt", "r") do |input|
  #   File.open("output.txt", "w") do |output|
  #     CharConv.convert(input, output, "Shift_JIS", "UTF-8")
  #   end
  # end
  # ```
  def self.convert(input : IO, output : IO, from : String, to : String, buffer_size : Int32 = 8192)
    converter = Converter.new(from, to)
    converter.convert(input, output, buffer_size)
  end

  # Returns `true` if the given encoding *name* is supported.
  #
  # Accepts canonical names and aliases. The `//IGNORE` and `//TRANSLIT` suffixes
  # are stripped before lookup.
  #
  # ```
  # CharConv.encoding_supported?("UTF-8")       # => true
  # CharConv.encoding_supported?("SHIFT_JIS")    # => true
  # CharConv.encoding_supported?("NONEXISTENT")  # => false
  # ```
  def self.encoding_supported?(name : String) : Bool
    !Registry.lookup(name).nil?
  end

  # Returns an array of all canonical encoding names.
  #
  # ```
  # CharConv.list_encodings # => ["ASCII", "UTF-8", "ISO-8859-1", ...]
  # ```
  def self.list_encodings : Array(String)
    Registry.canonical_names
  end
end
