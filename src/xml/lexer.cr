class XML::Lexer
  getter token : Token

  def initialize(input)
    @token = Token.new
    @reader = Reader.new(input)
    @readable = true
  end

  def readable? : Bool
    @readable
  end

  def location : Tuple(Int32, Int32)
    {@reader.line_number, @reader.column_number}
  end

  def next_token : Token
    skip_to_content

    @token.line_number = @reader.line_number
    @token.column_number = @reader.column_number

    @token.name = @reader.name
    @token.value = @reader.value

    @token
  end

  private def skip_to_content : Nil
    @reader.read

    loop do
      case @reader.node_type
      when .text?
        break
      end

      @readable = @reader.read
    end

    nil
  end
end
