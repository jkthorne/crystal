class XML::Token
  enum Kind
    Null
    False
    True
    Int
    Float
    String
    EOF
  end

  property kind : Kind
  property line_number : Int32
  property column_number : Int32
  property raw_value : String

  def initialize
    @kind = Kind::EOF
    @line_number = 0
    @column_number = 0
    @raw_value = ""
  end

  def int_value : Int64
    raw_value.to_i64
  rescue exc : ArgumentError
    raise ParseException.new(exc.message, line_number, column_number)
  end

  def float_value : Float64
    raw_value.to_f64
  rescue exc : ArgumentError
    raise ParseException.new(exc.message, line_number, column_number)
  end

  def string_value : String
    @raw_value
  end
end
