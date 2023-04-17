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
  property name : String
  property value : String

  def initialize
    @kind = Kind::EOF
    @line_number = 0
    @column_number = 0
    @name = ""
    @value = ""
  end
end
