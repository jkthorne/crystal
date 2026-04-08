struct BigDecimal < Number
  include Comparable(Int)
  include Comparable(Float)
  include Comparable(BigRational)
  include Comparable(BigDecimal)

  # Default precision (number of decimal digits) used for division.
  DEFAULT_PRECISION = 100_u64

  # :nodoc:
  getter inner : BigNumber::BigDecimal

  # :nodoc:
  def initialize(@inner : BigNumber::BigDecimal)
  end

  # Creates a `BigDecimal` from a `BigInt` value and `UInt64` scale.
  def initialize(value : BigInt, scale : UInt64)
    @inner = BigNumber::BigDecimal.new(value.inner, scale)
  end

  # Creates a `BigDecimal` from an `Int` with an optional scale.
  def initialize(num : Int = 0, scale : Int = 0)
    @inner = BigNumber::BigDecimal.new(num, scale)
  end

  # Creates a `BigDecimal` from a `BigInt` with an optional scale.
  def initialize(num : BigInt, scale : Int = 0)
    @inner = BigNumber::BigDecimal.new(num.inner, scale)
  end

  # Creates a `BigDecimal` from a decimal string.
  def initialize(str : String)
    @inner = BigNumber::BigDecimal.new(str)
  end

  # Creates a `BigDecimal` from a `Float`.
  def self.new(num : Float) : self
    raise ArgumentError.new "Can only construct from a finite number" unless num.finite?
    new(num.to_s)
  end

  # Creates a `BigDecimal` from a `BigRational`.
  def self.new(num : BigRational) : self
    new(num.inner.to_big_d)
  end

  # Returns *num* (identity).
  def self.new(num : BigDecimal) : self
    num
  end

  # --- Accessors ---

  # Returns the unscaled `BigInt` value.
  def value : BigInt
    BigInt.new(@inner.value)
  end

  # Returns the scale.
  delegate :scale, to: @inner

  # --- Predicates ---

  # Delegates `zero?`, `positive?`, `negative?`, `sign`, and `integer?`.
  delegate :zero?, :positive?, :negative?, :sign, :integer?, to: @inner

  # --- Comparison ---

  # Compares with another `BigDecimal`.
  def <=>(other : BigDecimal) : Int32
    @inner <=> other.inner
  end

  # Compares with a `BigRational`.
  def <=>(other : BigRational) : Int32
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
  def ==(other : BigDecimal) : Bool
    @inner == other.inner
  end

  # --- Unary ---

  # Returns the negation.
  def - : BigDecimal
    BigDecimal.new(-@inner)
  end

  # --- Arithmetic ---

  # Returns the sum.
  def +(other : BigDecimal) : BigDecimal
    BigDecimal.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : BigInt) : BigDecimal
    BigDecimal.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : Int) : BigDecimal
    BigDecimal.new(@inner + other)
  end

  # Returns the difference.
  def -(other : BigDecimal) : BigDecimal
    BigDecimal.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : BigInt) : BigDecimal
    BigDecimal.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : Int) : BigDecimal
    BigDecimal.new(@inner - other)
  end

  # Returns the product.
  def *(other : BigDecimal) : BigDecimal
    BigDecimal.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : BigInt) : BigDecimal
    BigDecimal.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : Int) : BigDecimal
    BigDecimal.new(@inner * other)
  end

  # Returns the remainder.
  def %(other : BigDecimal) : BigDecimal
    BigDecimal.new(@inner % other.inner)
  end

  # Returns the remainder.
  def %(other : Int) : BigDecimal
    BigDecimal.new(@inner % other)
  end

  # Returns the quotient using `DEFAULT_PRECISION`.
  def /(other : BigDecimal) : BigDecimal
    BigDecimal.new(@inner / other.inner)
  end

  # Returns the quotient.
  def /(other : BigInt) : BigDecimal
    BigDecimal.new(@inner / other.inner)
  end

  # Returns the quotient.
  def /(other : Int) : BigDecimal
    BigDecimal.new(@inner / other)
  end

  # Divides with explicit decimal digit *precision*.
  def div(other : BigDecimal, precision : Int = DEFAULT_PRECISION) : BigDecimal
    BigDecimal.new(@inner.div(other.inner, precision))
  end

  # --- Exponentiation ---

  # Returns `self` raised to the power *other*.
  def **(other : Int) : BigDecimal
    BigDecimal.new(@inner ** other)
  end

  # --- Rounding ---

  # Rounds towards positive infinity.
  def ceil : BigDecimal
    BigDecimal.new(@inner.ceil)
  end

  # Rounds towards negative infinity.
  def floor : BigDecimal
    BigDecimal.new(@inner.floor)
  end

  # Rounds towards zero.
  def trunc : BigDecimal
    BigDecimal.new(@inner.trunc)
  end

  # Rounds to nearest, ties to even.
  def round_even : BigDecimal
    BigDecimal.new(@inner.round_even)
  end

  # Rounds to nearest, ties away from zero.
  def round_away : BigDecimal
    BigDecimal.new(@inner.round_away)
  end

  # --- Scaling ---

  # Returns a new `BigDecimal` scaled to match *new_scale*'s scale.
  def scale_to(new_scale : BigDecimal) : BigDecimal
    BigDecimal.new(@inner.scale_to(new_scale.inner))
  end

  # --- Conversion ---

  # Delegates float/int conversion methods to the inner implementation.
  delegate :to_f64, :to_f32, :to_f, :to_f!, :to_f32!, :to_f64!, to: @inner
  delegate :to_i, :to_i!, :to_u, :to_u!, to: @inner
  delegate :to_i8, :to_i8!, :to_i16, :to_i16!, :to_i32, :to_i32!, :to_i64, :to_i64!, to: @inner
  delegate :to_u8, :to_u8!, :to_u16, :to_u16!, :to_u32, :to_u32!, :to_u64, :to_u64!, to: @inner

  # Returns `self`.
  def to_big_d : BigDecimal
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
  def inspect : String
    @inner.inspect
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    @inner.inspect(io)
  end

  # --- Misc ---

  # Returns `self` (value type, no copy needed).
  def clone : BigDecimal
    self
  end

  # :nodoc:
  def hash(hasher)
    hasher = @inner.hash(hasher)
    hasher
  end
end
