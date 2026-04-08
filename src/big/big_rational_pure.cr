struct BigRational < Number
  include Comparable(BigRational)
  include Comparable(Int)
  include Comparable(Float)

  # :nodoc:
  getter inner : BigNumber::BigRational

  # :nodoc:
  def initialize(@inner : BigNumber::BigRational)
  end

  # Creates a `BigRational` from *numerator* and *denominator* `BigInt` values.
  def initialize(numerator : BigInt, denominator : BigInt)
    @inner = BigNumber::BigRational.new(numerator.inner, denominator.inner)
  end

  # Creates a `BigRational` from *numerator* and *denominator* integers.
  def initialize(numerator : Int, denominator : Int)
    num = numerator.is_a?(BigInt) ? numerator.inner : BigNumber::BigInt.new(numerator)
    den = denominator.is_a?(BigInt) ? denominator.inner : BigNumber::BigInt.new(denominator)
    @inner = BigNumber::BigRational.new(num, den)
  end

  # Creates a `BigRational` from a `BigInt` (denominator = 1).
  def initialize(num : BigInt)
    @inner = BigNumber::BigRational.new(num.inner)
  end

  # Creates a `BigRational` from an `Int` (denominator = 1).
  def initialize(num : Int)
    @inner = BigNumber::BigRational.new(num)
  end

  # Creates a `BigRational` from a primitive `Float`.
  def self.new(num : Float::Primitive) : self
    new(BigNumber::BigRational.new(num))
  end

  # Creates a `BigRational` from a `BigFloat`.
  def self.new(num : BigFloat) : self
    new(num.inner.to_big_r)
  end

  # Returns *num* (identity).
  def self.new(num : BigRational) : self
    num
  end

  # Creates a `BigRational` from a `BigDecimal`.
  def self.new(num : BigDecimal) : self
    new(num.inner.to_big_r)
  end

  # Creates a `BigRational` from a string of the form `"numerator/denominator"` or a decimal.
  def initialize(str : String)
    @inner = BigNumber::BigRational.new(str)
  end

  # --- Accessors ---

  # Returns the numerator as a `BigInt`.
  def numerator : BigInt
    BigInt.new(@inner.numerator)
  end

  # Returns the denominator as a `BigInt`.
  def denominator : BigInt
    BigInt.new(@inner.denominator)
  end

  # --- Predicates ---

  # Delegates `zero?`, `positive?`, `negative?`, and `sign`.
  delegate :zero?, :positive?, :negative?, :sign, to: @inner

  # Returns `true` if the denominator is 1.
  def integer? : Bool
    @inner.integer?
  end

  # --- Comparison ---

  # Compares with another `BigRational`.
  def <=>(other : BigRational) : Int32
    @inner <=> other.inner
  end

  # Compares with a primitive `Float`. Returns `nil` if *other* is NaN.
  def <=>(other : Float::Primitive) : Int32?
    @inner <=> other
  end

  # Compares with a `BigFloat`.
  def <=>(other : BigFloat) : Int32
    # Convert BigFloat to BigRational for comparison
    @inner <=> other.inner.to_big_r
  end

  # Compares with a `BigInt`.
  def <=>(other : BigInt) : Int32
    @inner <=> other.inner
  end

  # Compares with a primitive `Int`.
  def <=>(other : Int) : Int32
    @inner <=> other
  end

  # Returns `true` if equal to *other*.
  def ==(other : BigRational) : Bool
    @inner == other.inner
  end

  # Returns `true` if equal to *other*.
  def ==(other : Int) : Bool
    @inner == other
  end

  # Returns `true` if equal to *other*.
  def ==(other : BigInt) : Bool
    @inner == other.inner
  end

  # --- Unary ---

  # Returns the negation.
  def - : BigRational
    BigRational.new(-@inner)
  end

  # Returns the absolute value.
  def abs : BigRational
    BigRational.new(@inner.abs)
  end

  # Returns the multiplicative inverse (reciprocal).
  def inv : BigRational
    BigRational.new(@inner.inv)
  end

  # --- Arithmetic ---

  # Returns the sum.
  def +(other : BigRational) : BigRational
    BigRational.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : BigInt) : BigRational
    BigRational.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : Int) : BigRational
    BigRational.new(@inner + other)
  end

  # Returns the difference.
  def -(other : BigRational) : BigRational
    BigRational.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : BigInt) : BigRational
    BigRational.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : Int) : BigRational
    BigRational.new(@inner - other)
  end

  # Returns the product.
  def *(other : BigRational) : BigRational
    BigRational.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : BigInt) : BigRational
    BigRational.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : Int) : BigRational
    BigRational.new(@inner * other)
  end

  # Returns the quotient.
  def /(other : BigRational) : BigRational
    BigRational.new(@inner / other.inner)
  end

  # Cross-type division
  Number.expand_div [BigInt, BigFloat, BigDecimal], BigRational

  # --- Floor division & modulo ---

  # Returns the floor division.
  def //(other : BigRational) : BigRational
    BigRational.new(@inner // other.inner)
  end

  # Returns the floor division.
  def //(other : BigInt) : BigRational
    BigRational.new(@inner // other.inner)
  end

  # Returns the floor division.
  def //(other : Int) : BigRational
    BigRational.new(@inner // other)
  end

  # Returns the floored modulo.
  def %(other : BigRational) : BigRational
    BigRational.new(@inner % other.inner)
  end

  # Returns the floored modulo.
  def %(other : BigInt) : BigRational
    BigRational.new(@inner % other.inner)
  end

  # Returns the floored modulo.
  def %(other : Int) : BigRational
    BigRational.new(@inner % other)
  end

  # Returns the truncated division.
  def tdiv(other : BigRational) : BigRational
    BigRational.new(@inner.tdiv(other.inner))
  end

  # Returns the truncated division.
  def tdiv(other : BigInt) : BigRational
    BigRational.new(@inner.tdiv(other.inner))
  end

  # Returns the truncated division.
  def tdiv(other : Int) : BigRational
    BigRational.new(@inner.tdiv(other))
  end

  # Returns the truncated remainder.
  def remainder(other : BigRational) : BigRational
    BigRational.new(@inner.remainder(other.inner))
  end

  # Returns the truncated remainder.
  def remainder(other : BigInt) : BigRational
    BigRational.new(@inner.remainder(other.inner))
  end

  # Returns the truncated remainder.
  def remainder(other : Int) : BigRational
    BigRational.new(@inner.remainder(other))
  end

  # --- Exponentiation ---

  # Returns `self` raised to the power *other*.
  def **(other : Int) : BigRational
    BigRational.new(@inner ** other)
  end

  # --- Shifts ---

  # Returns `self / 2^other` (right shift).
  def >>(other : Int) : BigRational
    BigRational.new(@inner >> other)
  end

  # Returns `self * 2^other` (left shift).
  def <<(other : Int) : BigRational
    BigRational.new(@inner << other)
  end

  # --- Rounding ---

  # Rounds towards positive infinity.
  def ceil : BigRational
    BigRational.new(@inner.ceil)
  end

  # Rounds towards negative infinity.
  def floor : BigRational
    BigRational.new(@inner.floor)
  end

  # Rounds towards zero.
  def trunc : BigRational
    BigRational.new(@inner.trunc)
  end

  # Rounds to nearest, ties away from zero.
  def round_away : BigRational
    BigRational.new(@inner.round_away)
  end

  # Rounds to nearest, ties to even.
  def round_even : BigRational
    BigRational.new(@inner.round_even)
  end

  # --- Conversion ---

  # Delegates float/int conversion methods to the inner implementation.
  delegate :to_f, :to_f32, :to_f64, :to_f!, :to_f32!, :to_f64!, to: @inner
  delegate :to_i, :to_i8, :to_i16, :to_i32, :to_i64, to: @inner
  delegate :to_u8, :to_u16, :to_u32, :to_u64, to: @inner

  # Returns `self`.
  def to_big_r : BigRational
    self
  end

  # Converts to `BigInt` (truncates).
  def to_big_i : BigInt
    BigInt.new(@inner.to_big_i)
  end

  # Converts to `BigFloat`.
  def to_big_f : BigFloat
    BigFloat.new(@inner.to_big_f)
  end

  # Converts to `BigDecimal`.
  def to_big_d : BigDecimal
    BigDecimal.new(@inner.to_big_d)
  end

  # --- Serialization ---

  # Returns the string representation as `"numerator/denominator"`.
  def to_s : String
    @inner.to_s
  end

  # Returns the string representation in the given *base*.
  def to_s(base : Int = 10) : String
    @inner.to_s(base)
  end

  # Writes the string representation to *io*.
  def to_s(io : IO) : Nil
    @inner.to_s(io)
  end

  # Writes the string representation in the given *base* to *io*.
  def to_s(io : IO, base : Int) : Nil
    @inner.to_s(io, base)
  end

  # :nodoc:
  def inspect : String
    to_s
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    to_s(io)
  end

  # --- Misc ---

  # Returns `self` (value type, no copy needed).
  def clone : BigRational
    self
  end

  # :nodoc:
  def hash(hasher)
    hasher = @inner.hash(hasher)
    hasher
  end
end

# Fixed-scale decimal arithmetic, drop-in replacement for Crystal's stdlib `BigDecimal`.
#
# Wraps `BigNumber::BigDecimal` and inherits from `Number`. Represented as
# an unscaled `BigInt` value and a `UInt64` scale.
#
# ```
# d = BigDecimal.new("0.1") + BigDecimal.new("0.2")
# d == BigDecimal.new("0.3") # => true (no floating-point error)
