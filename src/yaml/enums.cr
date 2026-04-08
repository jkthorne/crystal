module YAML
  enum EventKind
    NONE
    STREAM_START
    STREAM_END
    DOCUMENT_START
    DOCUMENT_END
    ALIAS
    SCALAR
    SEQUENCE_START
    SEQUENCE_END
    MAPPING_START
    MAPPING_END
  end

  enum ScalarStyle
    ANY
    PLAIN
    SINGLE_QUOTED
    DOUBLE_QUOTED
    LITERAL
    FOLDED

    def quoted?
      single_quoted? || double_quoted?
    end
  end

  enum SequenceStyle
    ANY
    BLOCK
    FLOW
  end

  enum MappingStyle
    ANY
    BLOCK
    FLOW
  end

  {% unless flag?(:use_libyaml) %}
    enum Encoding
      UTF8
      UTF16LE
      UTF16BE
    end
  {% end %}
end
