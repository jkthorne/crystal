require "./libxml2"

module XML
  class PullParser
    delegate token, to: @lexer
    delegate location, to: @lexer
    delegate readable?, to: @lexer
    delegate name, to: token
    delegate value, to: token

    def initialize(input)
      @lexer = Lexer.new(input)
      @bool_value = false
      @string_value = ""

      next_token
    end

    def read_null : Nil
      read_next
      nil
    end

    def read_int : Int64
      value.to_i64
    end

    def read_bool : Bool
      case value
      when "t", "true"
        true
      when "f", "false"
        false
      else
        raise "invalid bool"
      end
    end

    def read_bool_or_null : Bool?
      read_null_or { read_bool }
    end

    def read_float : Float64
      value.to_f64
    end

    def read_string : String
      value
    end

    def read_raw : String
      value
    end

    def read_null_or(&)
      if @kind.null?
        read_next
        nil
      else
        yield
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

    {% for type in [Bool,
                    Int8,
                    Int16,
                    Int32,
                    Int64,
                    UInt8,
                    UInt16,
                    UInt32,
                    UInt64,
                    Float32,
                    Float64,
                   ] %}
      # Reads an {{type}} value and returns it.
      #
      # If the value is not an integer or does not fit in a {{type}} variable, it returns `nil`.
      def read?(klass : {{type}}.class)
        {{type}}.new(value)
      rescue XML::ParseException | OverflowError
        nil
      end
    {% end %}

    # Reads a `String` value and returns it.
    #
    # If the value is not a `String`, returns `nil`.
    def read?(klass : String.class) : String?
      value
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
