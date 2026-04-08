# Extensions to Crystal's built-in `Int` types for interoperability with BigNumber.
#
# Adds conversion methods (`#to_big_i`, `#to_big_f`, `#to_big_r`, `#to_big_d`)
# and arithmetic/comparison operators so that expressions like `2 + BigNumber::BigInt.new(3)`
# work naturally.
#
# These extensions are loaded automatically by `require "big_number"`. For the stdlib
# drop-in replacement, use `require "big_number/stdlib"` instead (which provides its
# own set of extensions on primitive types).
struct Int
  # Converts this integer to a `BigNumber::BigFloat`.
  #
  # ```
  # 42.to_big_f # => BigNumber::BigFloat
  # ```
  def to_big_f(*, precision : Int32 = BigNumber::BigFloat.default_precision) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self, precision: precision)
  end

  # Converts this integer to a `BigNumber::BigRational` with denominator 1.
  def to_big_r : BigNumber::BigRational
    BigNumber::BigRational.new(self)
  end

  # Converts this integer to a `BigNumber::BigDecimal`.
  def to_big_d : BigNumber::BigDecimal
    BigNumber::BigDecimal.new(self)
  end

  # :nodoc:
  def +(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self) + other
  end

  # :nodoc:
  def -(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self) - other
  end

  # :nodoc:
  def *(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self) * other
  end

  # :nodoc:
  def /(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self) / other
  end

  # :nodoc:
  def <=>(other : BigNumber::BigFloat) : Int32
    -(other <=> self)
  end

  # :nodoc:
  def ==(other : BigNumber::BigFloat) : Bool
    other == self
  end

  # :nodoc:
  def +(other : BigNumber::BigRational) : BigNumber::BigRational
    BigNumber::BigRational.new(self) + other
  end

  # :nodoc:
  def -(other : BigNumber::BigRational) : BigNumber::BigRational
    BigNumber::BigRational.new(self) - other
  end

  # :nodoc:
  def *(other : BigNumber::BigRational) : BigNumber::BigRational
    BigNumber::BigRational.new(self) * other
  end

  # :nodoc:
  def /(other : BigNumber::BigRational) : BigNumber::BigRational
    BigNumber::BigRational.new(self) / other
  end

  # :nodoc:
  def <=>(other : BigNumber::BigRational) : Int32
    -(other <=> self)
  end

  # :nodoc:
  def ==(other : BigNumber::BigRational) : Bool
    other == self
  end

  # :nodoc:
  def +(other : BigNumber::BigInt) : BigNumber::BigInt
    BigNumber::BigInt.new(self) + other
  end

  # :nodoc:
  def &+(other : BigNumber::BigInt) : BigNumber::BigInt
    self + other
  end

  # :nodoc:
  def -(other : BigNumber::BigInt) : BigNumber::BigInt
    BigNumber::BigInt.new(self) - other
  end

  # :nodoc:
  def &-(other : BigNumber::BigInt) : BigNumber::BigInt
    self - other
  end

  # :nodoc:
  def *(other : BigNumber::BigInt) : BigNumber::BigInt
    BigNumber::BigInt.new(self) * other
  end

  # :nodoc:
  def &*(other : BigNumber::BigInt) : BigNumber::BigInt
    self * other
  end

  # :nodoc:
  def %(other : BigNumber::BigInt) : BigNumber::BigInt
    BigNumber::BigInt.new(self) % other
  end

  # :nodoc:
  def <=>(other : BigNumber::BigInt) : Int32
    -(other <=> self)
  end

  # :nodoc:
  def ==(other : BigNumber::BigInt) : Bool
    other == self
  end

  # Returns the greatest common divisor of `self` and *other*.
  # Uses binary GCD (Stein's algorithm) via `BigNumber::BigInt#gcd`.
  def gcd(other : BigNumber::BigInt) : Int
    BigNumber::BigInt.new(self).gcd(other).to_i64
  end

  # Returns the least common multiple of `self` and *other*.
  def lcm(other : BigNumber::BigInt) : BigNumber::BigInt
    BigNumber::BigInt.new(self).lcm(other)
  end

  # Converts this integer to a `BigNumber::BigInt`.
  #
  # ```
  # 42.to_big_i # => BigNumber::BigInt.new(42)
  # ```
  def to_big_i : BigNumber::BigInt
    BigNumber::BigInt.new(self)
  end
end

# Extensions to Crystal's built-in `Float` types for interoperability with BigNumber.
#
# Adds conversion methods and arithmetic operators so that floats can participate
# in mixed-type expressions with BigNumber types.
struct Float
  # Converts this float to a `BigNumber::BigFloat`.
  def to_big_f(*, precision : Int32 = BigNumber::BigFloat.default_precision) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self.to_f64, precision: precision)
  end

  # :nodoc:
  def +(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self.to_f64) + other
  end

  # :nodoc:
  def -(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self.to_f64) - other
  end

  # :nodoc:
  def *(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self.to_f64) * other
  end

  # :nodoc:
  def /(other : BigNumber::BigFloat) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self.to_f64) / other
  end

  # :nodoc:
  def <=>(other : BigNumber::BigFloat) : Int32?
    return nil if nan?
    -(other <=> self)
  end

  # Converts this float to a `BigNumber::BigRational` (exact rational representation).
  def to_big_r : BigNumber::BigRational
    BigNumber::BigRational.new(self)
  end

  # :nodoc:
  def <=>(other : BigNumber::BigInt) : Int32?
    return nil if nan?
    BigNumber::BigInt.new(self) <=> other
  end

  # Converts this float to a `BigNumber::BigInt` by truncating toward zero.
  # Raises `ArgumentError` if the float is non-finite (NaN or infinity).
  def to_big_i : BigNumber::BigInt
    BigNumber::BigInt.new(self)
  end

  # Converts this float to a `BigNumber::BigDecimal`.
  def to_big_d : BigNumber::BigDecimal
    BigNumber::BigDecimal.new(self)
  end
end

# Extensions to `String` for parsing BigNumber types from string representations.
class String
  # Parses this string as a `BigNumber::BigFloat`.
  #
  # ```
  # "3.14159".to_big_f # => BigNumber::BigFloat
  # ```
  def to_big_f(*, precision : Int32 = BigNumber::BigFloat.default_precision) : BigNumber::BigFloat
    BigNumber::BigFloat.new(self, precision: precision)
  end

  # Parses this string as a `BigNumber::BigInt` in the given *base* (default 10).
  #
  # ```
  # "123456789".to_big_i         # => BigNumber::BigInt (base 10)
  # "ff".to_big_i(base: 16)     # => BigNumber::BigInt (255)
  # ```
  def to_big_i(base : Int32 = 10) : BigNumber::BigInt
    BigNumber::BigInt.new(self, base)
  end

  # Parses this string as a `BigNumber::BigRational` (e.g., `"3/4"`).
  def to_big_r : BigNumber::BigRational
    BigNumber::BigRational.new(self)
  end

  # Parses this string as a `BigNumber::BigDecimal`.
  def to_big_d : BigNumber::BigDecimal
    BigNumber::BigDecimal.new(self)
  end
end

module BigNumber
  struct BigInt
    # Creates a `BigInt` from a floating-point number, truncating toward zero.
    # Raises `ArgumentError` if the float is non-finite (NaN or infinity).
    def initialize(num : Float::Primitive)
      @limbs = Pointer(Limb).null
      @alloc = 0
      @size = 0
      raise ArgumentError.new("Non-finite float") unless num.finite?
      return if num == 0
      neg = num < 0
      # Truncate toward zero
      mag = neg ? (-num).to_u128 : num.to_u128
      set_from_unsigned(mag)
      @size = -@size if neg
    end

    # Creates a copy of *other*.
    def initialize(other : BigInt)
      if other.zero?
        @limbs = Pointer(Limb).null
        @alloc = 0
        @size = 0
      else
        n = other.abs_size
        @alloc = n
        @limbs = Pointer(Limb).malloc(n)
        @limbs.copy_from(other.@limbs, n)
        @size = other.@size
      end
    end
  end
end
