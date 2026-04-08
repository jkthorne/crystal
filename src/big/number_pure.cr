# ==========================================================================
# Number.expand_div for primitive types (enables Int / BigInt -> BigFloat etc.)
# ==========================================================================
struct BigInt
  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], BigFloat
  Number.expand_div [Float32, Float64], BigFloat
end

struct BigFloat
  Number.expand_div [Float32, Float64], BigFloat
end

struct BigDecimal
  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], BigDecimal
  Number.expand_div [Float32, Float64], BigDecimal
end

struct BigRational
  Number.expand_div [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128], BigRational
  Number.expand_div [Float32, Float64], BigRational
end


# Extensions for primitive types, Math, Random, and Crystal::Hasher
# to complete the stdlib drop-in replacement.
#
# This file is required by stdlib.cr and should not be required directly.

# ==========================================================================
# Primitive type conversions — Int
# ==========================================================================

struct Int
  include Comparable(BigInt)
  include Comparable(BigRational)

  # Converts this integer to a `BigInt`.
  def to_big_i : BigInt
    BigInt.new(self)
  end

  # Converts this integer to a `BigFloat`.
  def to_big_f : BigFloat
    BigFloat.new(self)
  end

  # Converts this integer to a `BigRational` with denominator 1.
  def to_big_r : BigRational
    BigRational.new(self, 1)
  end

  # Converts this integer to a `BigDecimal` with scale 0.
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end

  # --- Arithmetic with BigInt ---

  # Returns the sum of this `Int` and a `BigInt`.
  def +(other : BigInt) : BigInt
    other + self
  end

  # Wrapping addition with `BigInt`.
  def &+(other : BigInt) : BigInt
    self + other
  end

  # Returns the difference of this `Int` and a `BigInt`.
  def -(other : BigInt) : BigInt
    BigInt.new(self) - other
  end

  # Wrapping subtraction with `BigInt`.
  def &-(other : BigInt) : BigInt
    self - other
  end

  # Returns the product of this `Int` and a `BigInt`.
  def *(other : BigInt) : BigInt
    other * self
  end

  # Wrapping multiplication with `BigInt`.
  def &*(other : BigInt) : BigInt
    self * other
  end

  # Returns the floored modulo of this `Int` by a `BigInt`.
  def %(other : BigInt) : BigInt
    BigInt.new(self) % other
  end

  # Compares this `Int` with a `BigInt`.
  def <=>(other : BigInt) : Int32
    -(other <=> self)
  end

  # Returns `true` if this `Int` equals the `BigInt`.
  def ==(other : BigInt) : Bool
    other == self
  end

  # Returns the GCD of this `Int` and a `BigInt`.
  def gcd(other : BigInt) : Int
    other.gcd(self)
  end

  # Returns the LCM of this `Int` and a `BigInt`.
  def lcm(other : BigInt) : BigInt
    other.lcm(self)
  end

  # --- Arithmetic with BigRational ---

  # Returns the sum of this `Int` and a `BigRational`.
  def +(other : BigRational) : BigRational
    other + self
  end

  # Returns the difference of this `Int` and a `BigRational`.
  def -(other : BigRational) : BigRational
    self.to_big_r - other
  end

  # Returns the product of this `Int` and a `BigRational`.
  def *(other : BigRational) : BigRational
    other * self
  end

  # Returns the quotient of this `Int` and a `BigRational`.
  def /(other : BigRational)
    self.to_big_r / other
  end

  # Compares this `Int` with a `BigRational`.
  def <=>(other : BigRational) : Int32
    -(other <=> self)
  end

  # --- Arithmetic with BigFloat ---

  # Compares this `Int` with a `BigFloat`.
  def <=>(other : BigFloat) : Int32
    -(other <=> self)
  end

  # Returns the difference of this `Int` and a `BigFloat`.
  def -(other : BigFloat) : BigFloat
    BigFloat.new(self) - other
  end

  # Returns the quotient of this `Int` and a `BigFloat`.
  def /(other : BigFloat) : BigFloat
    BigFloat.new(self) / other
  end
end

# ==========================================================================
# Primitive type conversions — Number
# ==========================================================================

struct Number
  include Comparable(BigFloat)

  # Returns the sum of this `Number` and a `BigFloat`.
  def +(other : BigFloat)
    other + self
  end

  # Returns the difference of this `Number` and a `BigFloat`.
  def -(other : BigFloat)
    to_big_f - other
  end

  # Returns the product of this `Number` and a `BigFloat`.
  def *(other : BigFloat) : BigFloat
    other * self
  end

  # Returns the quotient of this `Number` and a `BigFloat`.
  def /(other : BigFloat) : BigFloat
    to_big_f / other
  end

  # Converts this number to a `BigFloat`.
  def to_big_f : BigFloat
    BigFloat.new(self)
  end
end

# ==========================================================================
# Primitive type conversions — Float
# ==========================================================================

struct Float
  include Comparable(BigInt)
  include Comparable(BigRational)

  # Converts this float to a `BigInt` (truncates).
  def to_big_i : BigInt
    BigInt.new(self)
  end

  # Converts this float to a `BigFloat`.
  def to_big_f : BigFloat
    BigFloat.new(self.to_f64)
  end

  # Converts this float to an exact `BigRational`.
  def to_big_r : BigRational
    BigRational.new(self)
  end

  # Converts this float to a `BigDecimal`.
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end

  # Compares this `Float` with a `BigInt`.
  def <=>(other : BigInt)
    cmp = other <=> self
    -cmp if cmp
  end

  # Compares this `Float` with a `BigFloat`.
  def <=>(other : BigFloat)
    cmp = other <=> self
    -cmp if cmp
  end

  # Compares this `Float` with a `BigRational`.
  def <=>(other : BigRational)
    cmp = other <=> self
    -cmp if cmp
  end

  # Returns `self / other` as the same float type.
  def fdiv(other : BigInt | BigFloat | BigDecimal | BigRational) : self
    self.class.new(self / other)
  end
end

# ==========================================================================
# Primitive type conversions — String
# ==========================================================================

class String
  # Parses this string as a `BigInt` in the given *base*.
  def to_big_i(base : Int32 = 10) : BigInt
    BigInt.new(self, base)
  end

  # Parses this string as a `BigFloat`.
  def to_big_f : BigFloat
    BigFloat.new(self)
  end

  # Parses this string as a `BigRational`.
  def to_big_r : BigRational
    BigRational.new(self)
  end

  # Parses this string as a `BigDecimal`.
  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end
end

# ==========================================================================
# Cross-type comparison additions
# ==========================================================================

struct BigFloat
  # Compares this `BigFloat` with a `BigRational`.
  def <=>(other : BigRational)
    -(other <=> self)
  end
end

# ==========================================================================
# Generic Number constructor for BigFloat
# ==========================================================================

struct BigFloat
  # Creates a `BigFloat` from any `Number` via `Float64` conversion.
  def initialize(num : Number)
    @inner = BigNumber::BigFloat.new(num.to_f64)
  end
end

# ==========================================================================
# Number.expand_div for each primitive type
# ==========================================================================

{% for type in [Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64, Int128, UInt128] %}
  struct {{type}}
    Number.expand_div [BigInt], BigFloat
    Number.expand_div [BigDecimal], BigDecimal
    Number.expand_div [BigRational], BigRational
  end
{% end %}

struct Float32
  Number.expand_div [BigInt], BigFloat
  Number.expand_div [BigFloat], BigFloat
  Number.expand_div [BigDecimal], BigDecimal
  Number.expand_div [BigRational], BigRational
end

struct Float64
  Number.expand_div [BigInt], BigFloat
  Number.expand_div [BigFloat], BigFloat
  Number.expand_div [BigDecimal], BigDecimal
  Number.expand_div [BigRational], BigRational
end

# ==========================================================================
# Math module — arbitrary-precision math functions
# ==========================================================================

module Math
  # Returns the integer square root of a `BigInt`.
  #
  # ```
  # Math.isqrt(BigInt.new(49)) # => 7
  # ```
  def isqrt(value : BigInt) : BigInt
    value.sqrt
  end

  # Returns the square root of a `BigInt` as a `BigFloat`.
  def sqrt(value : BigInt) : BigFloat
    sqrt(value.to_big_f)
  end

  # Returns the square root of a `BigFloat` using Newton's method.
  #
  # Raises `ArgumentError` if *value* is negative.
  def sqrt(value : BigFloat) : BigFloat
    raise ArgumentError.new("Square root of negative number") if value.negative?
    return BigFloat.new(0) if value.zero?

    # Newton's method: x_{n+1} = (x + value/x) / 2
    f64 = value.to_f64
    x = if f64.finite? && f64 > 0
          BigFloat.new(Math.sqrt(f64))
        else
          # For extreme values, start with a rough estimate
          BigFloat.new(1)
        end

    two = BigFloat.new(2)
    100.times do
      next_x = (x + value / x) / two
      break if next_x == x
      x = next_x
    end
    x
  end

  # Returns the square root of a `BigRational` as a `BigFloat`.
  def sqrt(value : BigRational) : BigFloat
    sqrt(value.to_big_f)
  end

  # Returns the smallest power of two greater than or equal to *v*.
  def pw2ceil(v : BigInt) : BigInt
    v.next_power_of_two
  end
end

# ==========================================================================
# Random — BigInt random number generation
# ==========================================================================

module Random
  # Generates a uniform random `BigInt` in `[0, max)`.
  private def rand_int(max : BigInt) : BigInt
    unless max > 0
      raise ArgumentError.new "Invalid bound for rand: #{max}"
    end

    rand_max = BigInt.new(1) << (sizeof(typeof(next_u)) * 8)
    needed_parts = 1
    while rand_max < max && rand_max > 0
      rand_max <<= sizeof(typeof(next_u)) * 8
      needed_parts += 1
    end

    limit = rand_max // max * max

    loop do
      result = BigInt.new(next_u)
      (needed_parts - 1).times do
        result <<= sizeof(typeof(next_u)) * 8
        result |= BigInt.new(next_u)
      end

      if result < limit
        return result % max
      end
    end
  end

  # Generates a uniform random `BigInt` within the given *range*.
  private def rand_range(range : Range(BigInt, BigInt)) : BigInt
    span = range.end - range.begin
    unless range.excludes_end?
      span += 1
    end
    unless span > 0
      raise ArgumentError.new "Invalid range for rand: #{range}"
    end
    range.begin + rand_int(span)
  end
end

# ==========================================================================
# Crystal::Hasher — numeric hash equality
#
# Ensures that numerically equal values across BigInt, BigFloat, BigRational,
# BigDecimal, and primitive types produce identical hash values.
# For example: `BigInt.new(42).hash == 42.hash`.
# ==========================================================================

# :nodoc:
struct Crystal::Hasher
  # Helper: reduce a BigNumber::BigInt mod HASH_MODULUS
  private def self.reduce_inner_bigint(value : BigNumber::BigInt) : UInt64
    modulus = BigNumber::BigInt.new(HASH_MODULUS)
    rem = value.remainder(modulus)
    v = rem.abs.to_u64!
    value.negative? ? &-v : v
  end

  # Modular inverse of a mod m using iterative extended GCD
  private def self.mod_inverse_u64(a : UInt64, m : UInt64) : UInt64
    return 0_u64 if a == 0
    old_r, r = a.to_i64!, m.to_i64!
    old_s, s = 1_i64, 0_i64

    while r != 0
      q = old_r // r
      old_r, r = r, old_r &- q &* r
      old_s, s = s, old_s &- q &* s
    end

    ((old_s % m.to_i64!) + m.to_i64!).to_u64! % m
  end

  # Modular exponentiation: base^exp mod m
  private def self.mod_pow_u64(base : UInt64, exp : UInt64, m : UInt64) : UInt64
    result = 1_u64
    base = base % m
    e = exp
    while e > 0
      if e.odd?
        result = UInt64.mulmod(result, base, m)
      end
      e >>= 1
      base = UInt64.mulmod(base, base, m) if e > 0
    end
    result
  end

  # Reduces a `BigInt` for numeric hashing.
  def self.reduce_num(value : ::BigInt) : UInt64
    reduce_inner_bigint(value.inner)
  end

  # Reduces a `BigFloat` for numeric hashing.
  def self.reduce_num(value : ::BigFloat) : UInt64
    inner = value.inner
    return 0_u64 if inner.zero?

    m = inner.mantissa  # BigNumber::BigInt
    e = inner.exponent  # Int64

    m_mod = reduce_inner_bigint(m.abs)

    # 2^(e mod HASH_BITS) mod HASH_MODULUS
    # Crystal's % on Int is floored, so negative e gives positive result
    exp_mod = (e % HASH_BITS).to_i32
    pow2 = 1_u64 << exp_mod

    x = UInt64.mulmod(m_mod, pow2, HASH_MODULUS.to_u64!)

    inner.negative? ? &-x : x
  end

  # Reduces a `BigRational` for numeric hashing.
  def self.reduce_num(value : ::BigRational) : UInt64
    inner = value.inner
    return 0_u64 if inner.zero?

    den_abs = inner.denominator.abs
    modulus = BigNumber::BigInt.new(HASH_MODULUS)
    den_mod = den_abs.remainder(modulus).to_u64!

    if den_mod == 0
      # Denominator is a multiple of HASH_MODULUS — treat as infinity
      return value >= 0 ? HASH_INF_PLUS : HASH_INF_MINUS
    end

    inv = mod_inverse_u64(den_mod, HASH_MODULUS.to_u64!)
    num_hash = reduce_inner_bigint(inner.numerator.abs)

    UInt64.mulmod(num_hash, inv, HASH_MODULUS.to_u64!) &* value.sign
  end

  # Reduces a `BigDecimal` for numeric hashing.
  def self.reduce_num(value : ::BigDecimal) : UInt64
    inner = value.inner
    return 0_u64 if inner.zero?

    v = inner.value  # BigNumber::BigInt (unscaled integer)
    s = inner.scale  # UInt64

    v_mod = reduce_inner_bigint(v.abs)

    if s == 0
      return v.negative? ? &-v_mod : v_mod
    end

    # Divide by 10^s mod HASH_MODULUS
    ten_pow_s = mod_pow_u64(10_u64, s, HASH_MODULUS.to_u64!)
    inv_ten = mod_inverse_u64(ten_pow_s, HASH_MODULUS.to_u64!)

    x = UInt64.mulmod(v_mod, inv_ten, HASH_MODULUS.to_u64!)

    v.negative? ? &-x : x
  end
end

# ==========================================================================
# Update wrapper hash methods to use proper numeric hashing
# ==========================================================================

struct BigInt
  # :nodoc:
  def hash(hasher)
    hasher.number(self)
  end
end

struct BigFloat
  # :nodoc:
  def hash(hasher)
    hasher.number(self)
  end
end

struct BigRational
  # :nodoc:
  def hash(hasher)
    hasher.number(self)
  end
end

struct BigDecimal
  # :nodoc:
  def hash(hasher)
    hasher.number(self)
  end
end
