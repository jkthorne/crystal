require "./libxml2"

module XML
  class PullParser
    enum Kind
      Null
      Bool
      Int
      Float
      String
      EOF
    end

    delegate token, to: @lexer
    delegate location, to: @lexer
    delegate readable, to: @lexer
    delegate raw_value, to: token

    getter string_value : String

    def initialize(input)
      @lexer = Lexer.new(input)
      @bool_value = false
      @string_value = ""

      next_token
      case token.kind
      in .null?
        @kind = Kind::Null
      in .false?
        @kind = Kind::Bool
        @bool_value = false
      in .true?
        @kind = Kind::Bool
        @bool_value = true
      in .int?
        @kind = Kind::Int
      in .float?
        @kind = Kind::Float
      in .string?
        @kind = Kind::String
        @string_value = token.string_value
      in .eof?
        @kind = Kind::EOF
      end
    end

    def int_value
      token.int_value
    end

    def float_value
      token.float_value
    end

    def read_null : Nil
      expect_kind Kind::Null
      read_next
      nil
    end

    def read_int : Int64
      expect_kind Kind::Int
      int_value.tap { read_next }
    end

    def read_bool : Bool
      expect_kind Kind::Bool
      @bool_value.tap { read_next }
    end

    def read_int : Int64
      expect_kind Kind::Int
      int_value.tap { read_next }
    end

    def read_float : Float64
      case @kind
      when .int?
        int_value.to_f.tap { read_next }
      when .float?
        float_value.tap { read_next }
      else
        raise "expecting int or float but was #{@kind}"
      end
    end

    def read_string : String
      expect_kind Kind::String
      @string_value.tap { read_next }
    end

    def read_raw : String
      case @kind
      when .null?
        read_next
        "null"
      when .bool?
        @bool_value.to_s.tap { read_next }
      when .int?, .float?
        read_next
        raw_value
      when .string?
        @string_value.tap { read_next }
      else
        unexpected_token
      end
    end

    private def next_token
      @location = {@lexer.token.line_number, @lexer.token.column_number}
      @lexer.next_token
      token
    end

    def read_next
      next_token
      @kind
    end

    private def expect_kind(kind : Kind)
      raise "Expected #{kind} but was #{@kind}" unless @kind == kind
    end

    private def unexpected_token
      raise "Unexpected token: #{token}"
    end
  end

  class ParseException < XML::Error
    getter line_number : Int32
    getter column_number : Int32

    def initialize(message, @line_number = 0, @column_number = 0, cause = nil)
      super(
        "#{message} at line #{@line_number}, column #{@column_number}",
        line_number,
        column_number,
        cause
      )
    end

    def location : {Int32, Int32}
      {line_number, column_number}
    end
  end
end
