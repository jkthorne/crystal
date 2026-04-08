struct BigFloat < Float
  include Comparable(Int)
  include Comparable(BigFloat)
  include Comparable(Float)

  # :nodoc:
  getter inner : BigNumber::BigFloat

  # :nodoc:
  def initialize(@inner : BigNumber::BigFloat)
  end

  # Creates a `BigFloat` with value zero.
  def initialize
    @inner = BigNumber::BigFloat.new
  end

  # Creates a `BigFloat` from a decimal string.
  def initialize(str : String)
    @inner = BigNumber::BigFloat.new(str)
  end

  # Creates a `BigFloat` from an `Int`.
  def initialize(num : Int)
    @inner = BigNumber::BigFloat.new(num)
  end

  # Creates a `BigFloat` from a `BigInt`.
  def initialize(num : BigInt)
    @inner = BigNumber::BigFloat.new(num.inner)
  end

  # Creates a `BigFloat` from a primitive `Float`.
  def initialize(num : Float::Primitive)
    @inner = BigNumber::BigFloat.new(num)
  end

  # Creates a `BigFloat` from a `BigRational`.
  def initialize(num : BigRational)
    @inner = BigNumber::BigFloat.new(num.inner)
  end

  # Creates a `BigFloat` from another `BigFloat` (copies inner).
  def initialize(num : BigFloat)
    @inner = num.inner
  end

  # Returns *num* (identity).
  def self.new(num : BigFloat) : self
    num
  end

  # Creates a `BigFloat` from a `BigDecimal`.
  def self.new(num : BigDecimal) : self
    new(num.inner.to_big_f)
  end

  # Creates a zero-valued `BigFloat` with the given *precision* in bits.
  def initialize(*, precision : Int32)
    @inner = BigNumber::BigFloat.new(precision: precision)
  end

  # Creates a `BigFloat` from an `Int` with the given *precision* in bits.
  def initialize(num : Int, *, precision : Int32)
    @inner = BigNumber::BigFloat.new(num, precision: precision)
  end

  # Creates a `BigFloat` from a `BigInt` with the given *precision* in bits.
  def initialize(num : BigInt, *, precision : Int32)
    @inner = BigNumber::BigFloat.new(num.inner, precision: precision)
  end

  # Creates a `BigFloat` from a primitive `Float` with the given *precision* in bits.
  def initialize(num : Float::Primitive, precision : Int)
    @inner = BigNumber::BigFloat.new(num, precision: precision.to_i32)
  end

  # Creates a `BigFloat` from a string with the given *precision* in bits.
  def initialize(str : String, precision : Int)
    @inner = BigNumber::BigFloat.new(str, precision: precision.to_i32)
  end

  # Returns the current default precision in bits.
  def self.default_precision : Int32
    BigNumber::BigFloat.default_precision
  end

  # Sets the default precision in bits for new `BigFloat` values.
  def self.default_precision=(value : Int32) : Nil
    BigNumber::BigFloat.default_precision = value
  end

  # --- Predicates ---

  # Delegates `zero?`, `positive?`, `negative?`, and `precision`.
  delegate :zero?, :positive?, :negative?, :precision, to: @inner

  # Always returns `false` (`BigFloat` cannot be NaN).
  def nan? : Bool
    false
  end

  # Always returns `nil` (`BigFloat` cannot be infinite).
  def infinite? : Int32?
    nil
  end

  # Returns `true` if the fractional part is zero.
  def integer? : Bool
    @inner.integer?
  end

  # Returns the sign as -1, 0, or 1.
  def sign : Int32
    @inner.sign_i32
  end

  # --- Accessors ---

  # Returns the mantissa as a `BigInt`.
  def mantissa : BigInt
    BigInt.new(@inner.mantissa)
  end

  # Returns the binary exponent.
  delegate :exponent, to: @inner

  # --- Comparison ---

  # Compares with another `BigFloat`.
  def <=>(other : BigFloat) : Int32
    @inner <=> other.inner
  end

  # Compares with a `BigInt`.
  def <=>(other : BigInt) : Int32
    @inner <=> other.inner
  end

  # Compares with a primitive `Float`. Returns `nil` if *other* is NaN.
  def <=>(other : Float::Primitive) : Int32?
    @inner <=> other
  end

  # Compares with a primitive `Int`.
  def <=>(other : Int) : Int32
    @inner <=> other
  end

  # Returns `true` if equal to *other*.
  def ==(other : BigFloat) : Bool
    @inner == other.inner
  end

  # Returns `true` if equal to *other*.
  def ==(other : BigInt) : Bool
    @inner == other.inner
  end

  # Returns `true` if equal to *other*.
  def ==(other : Int) : Bool
    @inner == other
  end

  # Returns `true` if equal to *other*.
  def ==(other : Float) : Bool
    @inner == other
  end

  # --- Unary ---

  # Returns the negation.
  def - : BigFloat
    BigFloat.new(-@inner)
  end

  # Returns the absolute value.
  def abs : BigFloat
    BigFloat.new(@inner.abs)
  end

  # --- Arithmetic ---

  # Returns the sum.
  def +(other : BigFloat) : BigFloat
    BigFloat.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : BigInt) : BigFloat
    BigFloat.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : Int) : BigFloat
    BigFloat.new(@inner + other)
  end

  # Returns the sum.
  def +(other : Float) : BigFloat
    BigFloat.new(@inner + other)
  end

  # Returns the difference.
  def -(other : BigFloat) : BigFloat
    BigFloat.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : BigInt) : BigFloat
    BigFloat.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : Int) : BigFloat
    BigFloat.new(@inner - other)
  end

  # Returns the difference.
  def -(other : Float) : BigFloat
    BigFloat.new(@inner - other)
  end

  # Returns the product.
  def *(other : BigFloat) : BigFloat
    BigFloat.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : BigInt) : BigFloat
    BigFloat.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : Int) : BigFloat
    BigFloat.new(@inner * other)
  end

  # Returns the product.
  def *(other : Float) : BigFloat
    BigFloat.new(@inner * other)
  end

  # Returns the quotient.
  def /(other : BigFloat) : BigFloat
    BigFloat.new(@inner / other.inner)
  end

  # Returns the quotient.
  def /(other : BigInt) : BigFloat
    BigFloat.new(@inner / other.inner)
  end

  # Returns the quotient.
  def /(other : Int) : BigFloat
    BigFloat.new(@inner / other)
  end

  # Returns the quotient.
  def /(other : Float) : BigFloat
    BigFloat.new(@inner / other)
  end

  # Cross-type division
  Number.expand_div [BigDecimal], BigDecimal
  Number.expand_div [BigRational], BigRational

  # --- Exponentiation ---

  # Returns `self` raised to the power *other*.
  def **(other : Int) : BigFloat
    BigFloat.new(@inner ** other)
  end

  # Returns `self` raised to the power *other*.
  def **(other : BigInt) : BigFloat
    BigFloat.new(@inner ** other.inner)
  end

  # --- Rounding ---

  # Rounds towards positive infinity.
  def ceil : BigFloat
    BigFloat.new(@inner.ceil)
  end

  # Rounds towards negative infinity.
  def floor : BigFloat
    BigFloat.new(@inner.floor)
  end

  # Rounds towards zero.
  def trunc : BigFloat
    BigFloat.new(@inner.trunc)
  end

  # Rounds to nearest, ties to even.
  def round_even : BigFloat
    BigFloat.new(@inner.round_even)
  end

  # Rounds to nearest, ties away from zero.
  def round_away : BigFloat
    BigFloat.new(@inner.round_away)
  end

  # --- Conversion ---

  # Delegates float/int conversion methods to the inner implementation.
  delegate :to_f64, :to_f32, :to_f, :to_f32!, :to_f64!, :to_f!, to: @inner
  delegate :to_i, :to_i!, :to_u, :to_u!, to: @inner
  delegate :to_i8, :to_i8!, :to_i16, :to_i16!, :to_i32, :to_i32!, :to_i64, :to_i64!, to: @inner
  delegate :to_u8, :to_u8!, :to_u16, :to_u16!, :to_u32, :to_u32!, :to_u64, :to_u64!, to: @inner

  # Returns `self`.
  def to_big_f : BigFloat
    self
  end

  # Converts to `BigInt` (truncates).
  def to_big_i : BigInt
    BigInt.new(@inner.to_big_i)
  end

  # Converts to `BigRational`.
  def to_big_r : BigRational
    BigRational.new(@inner.to_big_r)
  end

  # --- Serialization ---

  # Returns the string representation.
  def to_s : String
    @inner.to_s
  end

  # Writes the string representation to *io*.
  def to_s(io : IO) : Nil
    @inner.to_s(io)
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    @inner.inspect(io)
  end

  # :nodoc:
  # Compatibility with GMP BigFloat's to_s_impl.
  protected def to_s_impl(*, point_range : Range, int_trailing_zeros : Bool) : String
    String.build { |io| to_s_impl(io, point_range: point_range, int_trailing_zeros: int_trailing_zeros) }
  end

  # :nodoc:
  protected def to_s_impl(io : IO, *, point_range : Range, int_trailing_zeros : Bool) : Nil
    io << to_s
  end

  # --- Misc ---

  # Returns `self` (value type, no copy needed).
  def clone : BigFloat
    self
  end

  # :nodoc:
  def hash(hasher)
    hasher = @inner.hash(hasher)
    hasher
  end

  # Returns `self / other` as `BigFloat`.
  def fdiv(other : Number::Primitive) : self
    self.class.new(self / other)
  end

  # Override `Number#format` to avoid `Float::Printer.shortest` which only
  # accepts `Float::Primitive`. Uses string conversion instead.
  def format(io : IO, separator = '.', delimiter = ',', decimal_places : Int? = nil, *, group : Int = 3, only_significant : Bool = false) : Nil
    number = self
    if decimal_places
      number = number.round(decimal_places)
    end

    if decimal_places && decimal_places >= 0
      string = number.abs.to_s
      # Ensure decimal point exists
      unless string.includes?('.')
        string = "#{string}.#{"0" * decimal_places}"
      end
      integer, _, decimals = string.partition('.')
    else
      string = number.abs.to_s
      _, _, decimals = string.partition(".")
      integer = number.trunc.to_big_i.abs.to_s
    end

    is_negative = number < 0

    format_impl(io, is_negative, integer, decimals, separator, delimiter, decimal_places, group, only_significant)
  end
end
