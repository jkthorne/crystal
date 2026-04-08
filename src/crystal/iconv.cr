{% if flag?(:use_libiconv) || flag?(:use_libc_iconv) %}
  # ── C library path (opt-in) ──────────────────────────────────────────────
  # Use system iconv when explicitly requested via -Duse_libiconv or -Duse_libc_iconv.

  {% if flag?(:use_libiconv) || flag?(:win32) || (flag?(:android) && LibC::ANDROID_API < 28) %}
    require "./lib_iconv"
    private USE_LIBICONV = true
  {% else %}
    require "c/iconv"
    private USE_LIBICONV = false
  {% end %}

  # :nodoc:
  struct Crystal::Iconv
    @skip_invalid : Bool

    {% if USE_LIBICONV %}
      @iconv : LibIconv::IconvT
    {% else %}
      @iconv : LibC::IconvT
    {% end %}

    ERROR = LibC::SizeT::MAX # (size_t)(-1)

    def initialize(from : String, to : String, invalid : Symbol? = nil)
      original_from, original_to = from, to

      @skip_invalid = invalid == :skip
      {% unless flag?(:freebsd) || flag?(:musl) || flag?(:dragonfly) || flag?(:netbsd) || flag?(:solaris) %}
        if @skip_invalid
          from = "#{from}//IGNORE"
          to = "#{to}//IGNORE"
        end
      {% end %}

      @iconv = {{ USE_LIBICONV ? LibIconv : LibC }}.iconv_open(to, from)

      if @iconv.address == ERROR
        if Errno.value == Errno::EINVAL
          if original_from == "UTF-8"
            raise ArgumentError.new("Invalid encoding: #{original_to}")
          elsif original_to == "UTF-8"
            raise ArgumentError.new("Invalid encoding: #{original_from}")
          else
            raise ArgumentError.new("Invalid encoding: #{original_from} -> #{original_to}")
          end
        else
          raise RuntimeError.from_errno("iconv_open")
        end
      end
    end

    def self.new(from : String, to : String, invalid : Symbol? = nil, &)
      iconv = new(from, to, invalid)
      begin
        yield iconv
      ensure
        iconv.close
      end
    end

    def convert(inbuf : UInt8**, inbytesleft : LibC::SizeT*, outbuf : UInt8**, outbytesleft : LibC::SizeT*)
      {% if flag?(:freebsd) || flag?(:dragonfly) %}
        if @skip_invalid
          return LibC.__iconv(@iconv, inbuf, inbytesleft, outbuf, outbytesleft, LibC::ICONV_F_HIDE_INVALID, out invalids)
        end
      {% end %}
      {{ USE_LIBICONV ? LibIconv : LibC }}.iconv(@iconv, inbuf, inbytesleft, outbuf, outbytesleft)
    end

    def handle_invalid(inbuf, inbytesleft)
      if @skip_invalid
        # iconv will leave inbuf right at the beginning of the invalid sequence,
        # so we just skip that byte and later we'll try with the next one
        if inbytesleft.value > 0
          inbuf.value += 1
          inbytesleft.value -= 1
        end
      else
        case Errno.value
        when Errno::EINVAL
          raise ArgumentError.new "Incomplete multibyte sequence"
        when Errno::EILSEQ
          raise ArgumentError.new "Invalid multibyte sequence"
        else
          # All is good
        end
      end
    end

    def close
      if {{ USE_LIBICONV ? LibIconv : LibC }}.iconv_close(@iconv) == -1
        raise RuntimeError.from_errno("iconv_close")
      end
    end
  end

{% else %}
  # ── Pure Crystal path (default) ──────────────────────────────────────────
  # Uses CharConv, a pure Crystal implementation of iconv with zero C dependencies.

  require "../charconv"

  # :nodoc:
  struct Crystal::Iconv
    ERROR = LibC::SizeT::MAX # (size_t)(-1)

    @skip_invalid : Bool
    @converter : CharConv::Converter

    def initialize(from : String, to : String, invalid : Symbol? = nil)
      original_from, original_to = from, to

      @skip_invalid = invalid == :skip

      # Strip //IGNORE and //TRANSLIT flags from the from encoding —
      # charconv applies flags from the `to` encoding only.
      clean_from = from
      if idx = clean_from.index("//")
        clean_from = clean_from[0, idx]
      end

      to_enc = to
      {% unless flag?(:freebsd) || flag?(:musl) || flag?(:dragonfly) || flag?(:netbsd) || flag?(:solaris) %}
        if @skip_invalid && !to_enc.includes?("//IGNORE")
          to_enc = "#{to_enc}//IGNORE"
        end
      {% end %}

      begin
        @converter = CharConv::Converter.new(clean_from, to_enc)
      rescue ex : ArgumentError
        original_from_clean = clean_from
        original_to_clean = to
        if idx = original_to_clean.index("//")
          original_to_clean = original_to_clean[0, idx]
        end

        if original_from_clean == "UTF-8"
          raise ArgumentError.new("Invalid encoding: #{original_to_clean}")
        elsif original_to_clean == "UTF-8"
          raise ArgumentError.new("Invalid encoding: #{original_from_clean}")
        else
          raise ArgumentError.new("Invalid encoding: #{original_from_clean} -> #{original_to_clean}")
        end
      end
    end

    def self.new(from : String, to : String, invalid : Symbol? = nil, &)
      iconv = new(from, to, invalid)
      begin
        yield iconv
      ensure
        iconv.close
      end
    end

    def convert(inbuf : UInt8**, inbytesleft : LibC::SizeT*, outbuf : UInt8**, outbytesleft : LibC::SizeT*)
      # NULL inbuf = flush stateful encoder and reset
      if inbuf.null?
        dst = Bytes.new(outbuf.value, outbytesleft.value)
        written = @converter.flush_encoder(dst, 0)
        outbuf.value += written
        outbytesleft.value -= written
        @converter.reset
        return LibC::SizeT.new(0)
      end

      src = Bytes.new(inbuf.value, inbytesleft.value)
      dst = Bytes.new(outbuf.value, outbytesleft.value)

      consumed, written, status = @converter.convert_with_status(src, dst)

      inbuf.value += consumed
      inbytesleft.value -= consumed
      outbuf.value += written
      outbytesleft.value -= written

      case status
      in .ok?
        LibC::SizeT.new(0)
      in .e2_big?
        Errno.value = Errno::E2BIG
        ERROR
      in .eilseq?
        Errno.value = Errno::EILSEQ
        ERROR
      in .einval?
        Errno.value = Errno::EINVAL
        ERROR
      end
    end

    def handle_invalid(inbuf, inbytesleft)
      if @skip_invalid
        if inbytesleft.value > 0
          inbuf.value += 1
          inbytesleft.value -= 1
        end
      else
        case Errno.value
        when Errno::EINVAL
          raise ArgumentError.new "Incomplete multibyte sequence"
        when Errno::EILSEQ
          raise ArgumentError.new "Invalid multibyte sequence"
        else
          # All is good
        end
      end
    end

    def close
    end
  end

{% end %}
