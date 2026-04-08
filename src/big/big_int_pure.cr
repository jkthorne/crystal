class InvalidBigDecimalException < Exception
  def initialize(big_decimal_str : String, reason : String)
    super("Invalid BigDecimal: #{big_decimal_str} (#{reason})")
  end
end

# Arbitrary-precision integer, drop-in replacement for Crystal's stdlib `BigInt`.
#
# Wraps `BigNumber::BigInt` and inherits from `Int`, providing the same API
# as the GMP-backed stdlib version. All arithmetic, bitwise, comparison, and
# conversion operations are delegated to the pure-Crystal implementation.
#
# ```
# a = BigInt.new("123456789012345678901234567890")
# b = BigInt.new(42)
# a * b # => 5185185018518518513851851851380
# ```
struct BigInt < Int
  include Comparable(Int::Signed)
  include Comparable(Int::Unsigned)
  include Comparable(BigInt)
  include Comparable(Float)

  # :nodoc:
  getter inner : BigNumber::BigInt

  # :nodoc:
  def initialize(@inner : BigNumber::BigInt)
  end

  # Creates a `BigInt` with value zero.
  def initialize
    @inner = BigNumber::BigInt.new
  end

  # Creates a `BigInt` from a string in the given *base* (default 10).
  def initialize(str : String, base : Int32 = 10)
    @inner = BigNumber::BigInt.new(str, base)
  end

  # Creates a `BigInt` from a primitive integer.
  def self.new(num : Int::Primitive) : self
    new(BigNumber::BigInt.new(num))
  end

  # Creates a `BigInt` from a primitive float (truncates).
  def initialize(num : Float::Primitive)
    @inner = BigNumber::BigInt.new(num)
  end

  # Creates a `BigInt` from a `BigFloat` (truncates).
  def self.new(num : BigFloat) : self
    new(num.inner.to_big_i)
  end

  # Creates a `BigInt` from a `BigDecimal` (truncates).
  def self.new(num : BigDecimal) : self
    new(num.inner.to_big_i)
  end

  # Creates a `BigInt` from a `BigRational` (truncates).
  def self.new(num : BigRational) : self
    new(num.inner.to_big_i)
  end

  # Returns *num* (identity).
  def self.new(num : BigInt) : self
    num
  end

  # Creates a `BigInt` from an array of digit values in the given *base*.
  def self.from_digits(digits : Enumerable(Int), base : Int = 10) : self
    new(BigNumber::BigInt.from_digits(digits, base))
  end

  # Creates a `BigInt` from raw bytes in big-endian or little-endian order.
  def self.from_bytes(bytes : Bytes, big_endian : Bool = true) : self
    new(BigNumber::BigInt.from_bytes(bytes, big_endian))
  end

  # --- Predicates & accessors ---

  # Returns `true` if zero.
  # Returns `true` if negative.
  # Returns `true` if positive.
  # Returns `true` if even.
  # Returns `true` if odd.
  # Returns the number of limbs.
  # Returns the number of bits needed to represent the absolute value.
  # Returns the sign as -1, 0, or 1.
  delegate :zero?, :negative?, :positive?, :even?, :odd?, :abs_size, :bit_length, :sign, to: @inner

  # --- Comparison ---

  # Compares with another `BigInt`.
  def <=>(other : BigInt) : Int32
    @inner <=> other.inner
  end

  # Compares with a primitive `Int`.
  def <=>(other : Int) : Int32
    @inner <=> other
  end

  # Compares with a primitive `Float`. Returns `nil` if *other* is NaN.
  def <=>(other : Float::Primitive) : Int32?
    @inner <=> other
  end

  # Returns `true` if equal to *other*.
  def ==(other : BigInt) : Bool
    @inner == other.inner
  end

  # Returns `true` if equal to *other*.
  def ==(other : Int) : Bool
    @inner == other
  end

  # --- Unary ---

  # Returns the negation.
  def - : BigInt
    BigInt.new(-@inner)
  end

  # Returns the absolute value.
  def abs : BigInt
    BigInt.new(@inner.abs)
  end

  # --- Arithmetic ---

  # Returns the sum.
  def +(other : BigInt) : BigInt
    BigInt.new(@inner + other.inner)
  end

  # Returns the sum.
  def +(other : Int) : BigInt
    BigInt.new(@inner + other)
  end

  # Wrapping addition (same as `+` for `BigInt`).
  def &+(other) : BigInt
    self + other
  end

  # Returns the difference.
  def -(other : BigInt) : BigInt
    BigInt.new(@inner - other.inner)
  end

  # Returns the difference.
  def -(other : Int) : BigInt
    BigInt.new(@inner - other)
  end

  # Wrapping subtraction (same as `-` for `BigInt`).
  def &-(other) : BigInt
    self - other
  end

  # Returns the product.
  def *(other : BigInt) : BigInt
    BigInt.new(@inner * other.inner)
  end

  # Returns the product.
  def *(other : Int) : BigInt
    BigInt.new(@inner * other)
  end

  # Wrapping multiplication (same as `*` for `BigInt`).
  def &*(other) : BigInt
    self * other
  end

  # Cross-type division via Number.expand_div
  Number.expand_div [BigFloat], BigFloat
  Number.expand_div [BigDecimal], BigDecimal
  Number.expand_div [BigRational], BigRational

  # --- Floor division & modulo ---

  # Returns the floor division.
  def //(other : BigInt) : BigInt
    BigInt.new(@inner // other.inner)
  end

  # Returns the floor division.
  def //(other : Int) : BigInt
    BigInt.new(@inner // other)
  end

  # Returns the floored modulo.
  def %(other : BigInt) : BigInt
    BigInt.new(@inner % other.inner)
  end

  # Returns the floored modulo.
  def %(other : Int) : BigInt
    BigInt.new(@inner % other)
  end

  # Returns `{quotient, remainder}` using floored division.
  def divmod(number : BigInt) : {BigInt, BigInt}
    q, r = @inner.divmod(number.inner)
    {BigInt.new(q), BigInt.new(r)}
  end

  # Returns `{quotient, remainder}` using floored division.
  def divmod(number : Int) : {BigInt, BigInt}
    q, r = @inner.divmod(BigNumber::BigInt.new(number))
    {BigInt.new(q), BigInt.new(r)}
  end

  # Returns the truncated division (rounds towards zero).
  def tdiv(other : BigInt) : BigInt
    BigInt.new(@inner.tdiv(other.inner))
  end

  # Returns the truncated division (rounds towards zero).
  def tdiv(other : Int) : BigInt
    BigInt.new(@inner.tdiv(BigNumber::BigInt.new(other)))
  end

  # Returns the truncated remainder (sign matches dividend).
  def remainder(other : BigInt) : BigInt
    BigInt.new(@inner.remainder(other.inner))
  end

  # Returns the truncated remainder (sign matches dividend).
  def remainder(other : Int) : BigInt
    BigInt.new(@inner.remainder(BigNumber::BigInt.new(other)))
  end

  # --- Unsafe division variants ---

  # Floored division without zero check.
  def unsafe_floored_div(other : BigInt) : BigInt
    BigInt.new(@inner.unsafe_floored_div(other.inner))
  end

  # Floored division without zero check.
  def unsafe_floored_div(other : Int) : BigInt
    BigInt.new(@inner.unsafe_floored_div(BigNumber::BigInt.new(other)))
  end

  # Floored modulo without zero check.
  def unsafe_floored_mod(other : BigInt) : BigInt
    BigInt.new(@inner.unsafe_floored_mod(other.inner))
  end

  # Floored modulo without zero check.
  def unsafe_floored_mod(other : Int) : BigInt
    BigInt.new(@inner.unsafe_floored_mod(BigNumber::BigInt.new(other)))
  end

  # Truncated division without zero check.
  def unsafe_truncated_div(other : BigInt) : BigInt
    BigInt.new(@inner.unsafe_truncated_div(other.inner))
  end

  # Truncated division without zero check.
  def unsafe_truncated_div(other : Int) : BigInt
    BigInt.new(@inner.unsafe_truncated_div(BigNumber::BigInt.new(other)))
  end

  # Truncated modulo without zero check.
  def unsafe_truncated_mod(other : BigInt) : BigInt
    BigInt.new(@inner.unsafe_truncated_mod(other.inner))
  end

  # Truncated modulo without zero check.
  def unsafe_truncated_mod(other : Int) : BigInt
    BigInt.new(@inner.unsafe_truncated_mod(BigNumber::BigInt.new(other)))
  end

  # Returns `{quotient, remainder}` using floored division, without zero check.
  def unsafe_floored_divmod(number : BigInt) : {BigInt, BigInt}
    q, r = @inner.unsafe_floored_divmod(number.inner)
    {BigInt.new(q), BigInt.new(r)}
  end

  # Returns `{quotient, remainder}` using floored division, without zero check.
  def unsafe_floored_divmod(number : Int) : {BigInt, BigInt}
    q, r = @inner.unsafe_floored_divmod(BigNumber::BigInt.new(number))
    {BigInt.new(q), BigInt.new(r)}
  end

  # Returns `{quotient, remainder}` using truncated division, without zero check.
  def unsafe_truncated_divmod(number : BigInt) : {BigInt, BigInt}
    q, r = @inner.unsafe_truncated_divmod(number.inner)
    {BigInt.new(q), BigInt.new(r)}
  end

  # Returns `{quotient, remainder}` using truncated division, without zero check.
  def unsafe_truncated_divmod(number : Int) : {BigInt, BigInt}
    q, r = @inner.unsafe_truncated_divmod(BigNumber::BigInt.new(number))
    {BigInt.new(q), BigInt.new(r)}
  end

  # --- Exponentiation ---

  # Returns `self` raised to the power *other*.
  def **(other : Int) : BigInt
    BigInt.new(@inner ** other)
  end

  # Returns `self ** exp mod mod` using Montgomery multiplication for odd moduli.
  def pow_mod(exp : BigInt, mod : BigInt) : BigInt
    BigInt.new(@inner.pow_mod(exp.inner, mod.inner))
  end

  # Returns `self ** exp mod mod`.
  def pow_mod(exp : Int, mod : BigInt) : BigInt
    BigInt.new(@inner.pow_mod(exp, mod.inner))
  end

  # Returns `self ** exp mod mod`.
  def pow_mod(exp : BigInt | Int, mod : Int) : BigInt
    e = exp.is_a?(BigInt) ? exp.inner : exp
    BigInt.new(@inner.pow_mod(e, mod))
  end

  # --- Bitwise ---

  # Returns the bitwise NOT (ones' complement).
  def ~ : BigInt
    BigInt.new(~@inner)
  end

  # Returns `self` shifted left by *count* bits.
  def <<(count : Int) : BigInt
    BigInt.new(@inner << count)
  end

  # Returns `self` shifted right by *count* bits.
  def >>(count : Int) : BigInt
    BigInt.new(@inner >> count)
  end

  # Unsafe right shift (same as `>>` for `BigInt`).
  def unsafe_shr(count : Int) : self
    self >> count
  end

  # Returns the bit at *index* (0 or 1).
  def bit(index : Int) : Int32
    @inner.bit(index)
  end

  # Returns the number of set bits (population count).
  # Returns the number of trailing zero bits.
  delegate :popcount, :trailing_zeros_count, to: @inner

  # Returns the bitwise AND.
  def &(other : BigInt) : BigInt
    BigInt.new(@inner & other.inner)
  end

  # Returns the bitwise AND.
  def &(other : Int) : BigInt
    BigInt.new(@inner & other)
  end

  # Returns the bitwise OR.
  def |(other : BigInt) : BigInt
    BigInt.new(@inner | other.inner)
  end

  # Returns the bitwise OR.
  def |(other : Int) : BigInt
    BigInt.new(@inner | other)
  end

  # Returns the bitwise XOR.
  def ^(other : BigInt) : BigInt
    BigInt.new(@inner ^ other.inner)
  end

  # Returns the bitwise XOR.
  def ^(other : Int) : BigInt
    BigInt.new(@inner ^ other)
  end

  # --- Number theory ---

  # Returns the greatest common divisor of `self` and *other*.
  def gcd(other : BigInt) : BigInt
    BigInt.new(@inner.gcd(other.inner))
  end

  # Returns the greatest common divisor of `self` and *other*.
  def gcd(other : Int) : Int
    @inner.gcd(other)
  end

  # Returns the least common multiple of `self` and *other*.
  def lcm(other : BigInt) : BigInt
    BigInt.new(@inner.lcm(other.inner))
  end

  # Returns the least common multiple of `self` and *other*.
  def lcm(other : Int) : BigInt
    BigInt.new(@inner.lcm(other))
  end

  # Returns `self!` (factorial). `self` must be non-negative.
  def factorial : BigInt
    BigInt.new(@inner.factorial)
  end

  # Returns `true` if `self` is evenly divisible by *number*.
  def divisible_by?(number : BigInt) : Bool
    @inner.divisible_by?(number.inner)
  end

  # Returns `true` if `self` is evenly divisible by *number*.
  def divisible_by?(number : Int) : Bool
    @inner.divisible_by?(number)
  end

  # Returns `true` if `self` is a probable prime (deterministic up to 3.3e24).
  delegate :prime?, to: @inner

  # --- Roots & powers ---

  # Returns the integer square root.
  def sqrt : BigInt
    BigInt.new(@inner.sqrt)
  end

  # Returns the integer *n*th root.
  def root(n : Int) : BigInt
    BigInt.new(@inner.root(n))
  end

  # Returns the smallest power of two greater than or equal to `self`.
  def next_power_of_two : BigInt
    BigInt.new(@inner.next_power_of_two)
  end

  # :nodoc:
  def factor_by(number : Int) : {BigInt, UInt64}
    result, count = @inner.factor_by(number)
    {BigInt.new(result), count}
  end

  # --- Conversion ---

  # Delegates integer conversion methods to the inner implementation.
  delegate :to_i, :to_i!, :to_u, :to_u!, to: @inner
  delegate :to_i8, :to_i8!, :to_i16, :to_i16!, :to_i32, :to_i32!, :to_i64, :to_i64!, to: @inner
  delegate :to_u8, :to_u8!, :to_u16, :to_u16!, :to_u32, :to_u32!, :to_u64, :to_u64!, to: @inner
  delegate :to_i128, :to_i128!, :to_u128, :to_u128!, to: @inner
  delegate :to_f, :to_f32, :to_f64, :to_f!, :to_f32!, :to_f64!, to: @inner

  # Returns `self`.
  def to_big_i : BigInt
    self
  end

  # Converts to `BigFloat`.
  def to_big_f : BigFloat
    BigFloat.new(@inner.to_big_f)
  end

  # Converts to `BigRational` (denominator = 1).
  def to_big_r : BigRational
    BigRational.new(@inner.to_big_r)
  end

  # Converts to `BigDecimal` (scale = 0).
  def to_big_d : BigDecimal
    BigDecimal.new(@inner.to_big_d)
  end

  # --- Serialization ---

  # Returns the base-10 string representation.
  def to_s : String
    @inner.to_s
  end

  # Returns the string representation in the given *base*.
  def to_s(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : String
    @inner.to_s(base, precision: precision, upcase: upcase)
  end

  # Writes the base-10 string representation to *io*.
  def to_s(io : IO) : Nil
    @inner.to_s(io)
  end

  # Writes the string representation in the given *base* to *io*.
  def to_s(io : IO, base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Nil
    @inner.to_s(io, base, precision: precision, upcase: upcase)
  end

  # :nodoc:
  def inspect(io : IO) : Nil
    @inner.inspect(io)
  end

  # Returns the big-endian (default) or little-endian byte representation.
  def to_bytes(big_endian : Bool = true) : Bytes
    @inner.to_bytes(big_endian)
  end

  # Returns an array of digit values in the given *base* (least significant first).
  def digits(base : Int = 10) : Array(Int32)
    @inner.digits(base)
  end

  # --- Misc ---

  # Returns `self` (value type, no copy needed).
  def clone : BigInt
    self
  end

  # :nodoc:
  def hash(hasher)
    hasher = @inner.hash(hasher)
    hasher
  end
end

# Allow BigNumber::BigInt to accept the wrapper BigInt
module BigNumber
  struct BigInt
    def initialize(wrapper : ::BigInt)
      initialize(wrapper.inner)
    end
  end
end

# BigInt / BigInt → BigFloat (matches GMP stdlib behavior)
struct BigInt
  def /(other : BigInt) : BigFloat
    BigFloat.new(self) / BigFloat.new(other)
  end
end

# Provide LibGMP type aliases for spec compatibility
module LibGMP
  alias UI = UInt64
  alias SI = Int64
  alias Double = Float64
end
