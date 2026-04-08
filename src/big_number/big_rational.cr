module BigNumber
  # Arbitrary-precision exact rational number, represented as a numerator/denominator
  # pair of `BigInt` values. The fraction is always stored in canonical form: reduced
  # to lowest terms via binary GCD, with a positive denominator.
  #
  # ```
  # r = BigNumber::BigRational.new(3, 4)
  # r + BigNumber::BigRational.new(1, 4) # => 1
  # r * BigNumber::BigRational.new(2, 3) # => 1/2
  # ```
  struct BigRational
    include Comparable(BigRational)
    include Comparable(Int)
    include Comparable(BigInt)

    # Returns the numerator as a `BigInt`.
    getter numerator : BigInt

    # Returns the denominator as a `BigInt` (always positive after canonicalization).
    getter denominator : BigInt

    # Creates a rational from explicit `BigInt` numerator and denominator.
    # The result is automatically reduced to lowest terms.
    #
    # Raises `DivisionByZeroError` if *denominator* is zero.
    #
    # ```
    # BigNumber::BigRational.new(BigNumber::BigInt.new(6), BigNumber::BigInt.new(4)) # => 3/2
    # ```
    def initialize(@numerator : BigInt, @denominator : BigInt)
      canonicalize!
    end

    # Creates a rational from integer numerator and denominator.
    # The result is automatically reduced to lowest terms.
    #
    # Raises `DivisionByZeroError` if *den* is zero.
    #
    # ```
    # BigNumber::BigRational.new(6, 4) # => 3/2
    # ```
    def initialize(num : Int, den : Int)
      @numerator = BigInt.new(num)
      @denominator = BigInt.new(den)
      canonicalize!
    end

    # Creates a rational with the given `BigInt` value and denominator 1.
    #
    # ```
    # BigNumber::BigRational.new(BigNumber::BigInt.new(5)) # => 5
    # ```
    def initialize(value : BigInt)
      @numerator = value.clone
      @denominator = BigInt.new(1)
    end

    # Creates a rational with the given integer value and denominator 1.
    #
    # ```
    # BigNumber::BigRational.new(42) # => 42
    # ```
    def initialize(value : Int)
      @numerator = BigInt.new(value)
      @denominator = BigInt.new(1)
    end

    # Creates a rational from a `Float` by decomposing it into its exact
    # binary representation (mantissa * 2^exponent).
    #
    # Raises `ArgumentError` for non-finite floats (NaN, infinity).
    #
    # ```
    # BigNumber::BigRational.new(0.75) # => 3/4
    # ```
    def initialize(value : Float)
      raise ArgumentError.new("Non-finite float") unless value.finite?
      if value == 0.0
        @numerator = BigInt.new(0)
        @denominator = BigInt.new(1)
        return
      end

      # Decompose float into exact rational representation
      # value = mantissa * 2^exponent where mantissa is an integer
      neg = value < 0
      f = neg ? -value : value

      # Extract mantissa and exponent via frexp-style decomposition
      # Float64 has 52-bit mantissa; value = significand * 2^exp where 0.5 <= significand < 1
      # We need the integer mantissa: multiply by 2^53 and adjust exponent
      bits = value.unsafe_as(UInt64)
      exponent = ((bits >> 52) & 0x7FF).to_i32 - 1023 - 52
      mantissa = (bits & 0x000FFFFFFFFFFFFF_u64) | 0x0010000000000000_u64

      @numerator = BigInt.new(mantissa)
      if exponent >= 0
        @numerator = @numerator << exponent
        @denominator = BigInt.new(1)
      else
        @denominator = BigInt.new(1) << (-exponent)
      end

      @numerator = -@numerator if neg
      canonicalize!
    end

    # Parses a rational from a string. Supports two formats:
    # - `"numerator/denominator"` (e.g. `"3/4"`)
    # - Plain integer string (e.g. `"42"`, treated as denominator 1)
    #
    # ```
    # BigNumber::BigRational.new("3/4")  # => 3/4
    # BigNumber::BigRational.new("-7")   # => -7
    # ```
    def initialize(str : String)
      if str.includes?('/')
        parts = str.split('/', 2)
        @numerator = BigInt.new(parts[0].strip)
        @denominator = BigInt.new(parts[1].strip)
        canonicalize!
      else
        @numerator = BigInt.new(str.strip)
        @denominator = BigInt.new(1)
      end
    end

    # --- Arithmetic ---

    # Returns the sum of `self` and *other*.
    def +(other : BigRational) : BigRational
      # a/b + c/d = (a*d + c*b) / (b*d)
      BigRational.new(
        @numerator * other.denominator + other.numerator * @denominator,
        @denominator * other.denominator
      )
    end

    # :ditto:
    def +(other : Int) : BigRational
      self + BigRational.new(other)
    end

    # :ditto:
    def +(other : BigInt) : BigRational
      self + BigRational.new(other)
    end

    # Returns the difference of `self` and *other*.
    def -(other : BigRational) : BigRational
      BigRational.new(
        @numerator * other.denominator - other.numerator * @denominator,
        @denominator * other.denominator
      )
    end

    # :ditto:
    def -(other : Int) : BigRational
      self - BigRational.new(other)
    end

    # :ditto:
    def -(other : BigInt) : BigRational
      self - BigRational.new(other)
    end

    # Returns the negation of `self`.
    def - : BigRational
      BigRational.new(-@numerator, @denominator.clone)
    end

    # Returns the product of `self` and *other*.
    def *(other : BigRational) : BigRational
      BigRational.new(
        @numerator * other.numerator,
        @denominator * other.denominator
      )
    end

    # :ditto:
    def *(other : Int) : BigRational
      self * BigRational.new(other)
    end

    # :ditto:
    def *(other : BigInt) : BigRational
      self * BigRational.new(other)
    end

    # Returns the quotient of `self` divided by *other*.
    #
    # Raises `DivisionByZeroError` if *other* is zero.
    def /(other : BigRational) : BigRational
      raise DivisionByZeroError.new if other.numerator.zero?
      BigRational.new(
        @numerator * other.denominator,
        @denominator * other.numerator
      )
    end

    # :ditto:
    def /(other : Int) : BigRational
      self / BigRational.new(other)
    end

    # :ditto:
    def /(other : BigInt) : BigRational
      self / BigRational.new(other)
    end

    # Returns the floor division of `self` by *other* (rounds toward negative infinity).
    #
    # Raises `DivisionByZeroError` if *other* is zero.
    def //(other : BigRational) : BigRational
      raise DivisionByZeroError.new if other.numerator.zero?
      BigRational.new((@numerator * other.denominator) // (@denominator * other.numerator))
    end

    # :ditto:
    def //(other : Int) : BigRational
      raise DivisionByZeroError.new if other == 0
      BigRational.new(@numerator // (@denominator * BigInt.new(other)))
    end

    # :ditto:
    def //(other : BigInt) : BigRational
      self // BigRational.new(other)
    end

    # Returns the modulo of `self` divided by *other* (floor remainder).
    #
    # Raises `DivisionByZeroError` if *other* is zero.
    def %(other : BigRational) : BigRational
      raise DivisionByZeroError.new if other.numerator.zero?
      BigRational.new(
        (@numerator * other.denominator) % (@denominator * other.numerator),
        @denominator * other.denominator
      )
    end

    # :ditto:
    def %(other : Int) : BigRational
      raise DivisionByZeroError.new if other == 0
      BigRational.new(@numerator % (@denominator * BigInt.new(other)), @denominator)
    end

    # :ditto:
    def %(other : BigInt) : BigRational
      self % BigRational.new(other)
    end

    # Returns the truncated division of `self` by *other* (rounds toward zero).
    #
    # Raises `DivisionByZeroError` if *other* is zero.
    def tdiv(other : BigRational) : BigRational
      raise DivisionByZeroError.new if other.numerator.zero?
      BigRational.new((@numerator * other.denominator).tdiv(@denominator * other.numerator))
    end

    # :ditto:
    def tdiv(other : Int) : BigRational
      raise DivisionByZeroError.new if other == 0
      BigRational.new(@numerator.tdiv(@denominator * BigInt.new(other)))
    end

    # :ditto:
    def tdiv(other : BigInt) : BigRational
      tdiv(BigRational.new(other))
    end

    # Returns the truncated remainder of `self` divided by *other*.
    # The sign of the result matches the sign of `self`.
    #
    # Raises `DivisionByZeroError` if *other* is zero.
    def remainder(other : BigRational) : BigRational
      raise DivisionByZeroError.new if other.numerator.zero?
      BigRational.new(
        (@numerator * other.denominator).remainder(@denominator * other.numerator),
        @denominator * other.denominator
      )
    end

    # :ditto:
    def remainder(other : Int) : BigRational
      raise DivisionByZeroError.new if other == 0
      BigRational.new(@numerator.remainder(@denominator * BigInt.new(other)), @denominator)
    end

    # :ditto:
    def remainder(other : BigInt) : BigRational
      remainder(BigRational.new(other))
    end

    # Raises `self` to the given *exponent* using binary exponentiation.
    # Negative exponents invert the rational first.
    #
    # ```
    # BigNumber::BigRational.new(2, 3) ** 3  # => 8/27
    # BigNumber::BigRational.new(2, 3) ** -1 # => 3/2
    # ```
    def **(exponent : Int) : BigRational
      if exponent == 0
        return BigRational.new(1)
      elsif exponent < 0
        inv ** (-exponent)
      elsif exponent == 1
        clone
      else
        # Binary exponentiation
        result = BigRational.new(1)
        base = clone
        exp = exponent
        while exp > 0
          result = result * base if exp.odd?
          base = base * base
          exp >>= 1
        end
        result
      end
    end

    # --- Comparison ---

    # Compares `self` with *other* by cross-multiplying numerators and denominators.
    def <=>(other : BigRational) : Int32
      # a/b <=> c/d  =>  a*d <=> c*b (denominators always positive)
      left = @numerator * other.denominator
      right = other.numerator * @denominator
      left <=> right
    end

    # :ditto:
    def <=>(other : Int) : Int32
      self <=> BigRational.new(other)
    end

    # :ditto:
    def <=>(other : BigInt) : Int32
      self <=> BigRational.new(other)
    end

    # Compares with a primitive float. Returns `nil` for NaN.
    def <=>(other : Float::Primitive) : Int32?
      return nil if other.nan?
      if other.infinite?
        return other > 0 ? -1 : 1
      end
      self <=> BigRational.new(other)
    end

    # Returns `true` if `self` and *other* represent the same value.
    def ==(other : BigRational) : Bool
      @numerator == other.numerator && @denominator == other.denominator
    end

    # :ditto:
    def ==(other : Int) : Bool
      @denominator == BigInt.new(1) && @numerator == BigInt.new(other)
    end

    # :ditto:
    def ==(other : BigInt) : Bool
      @denominator == BigInt.new(1) && @numerator == other
    end

    # --- Predicates ---

    # Returns `true` if the value is zero.
    def zero? : Bool
      @numerator.zero?
    end

    # Returns `true` if the value is strictly positive.
    def positive? : Bool
      @numerator.positive?
    end

    # Returns `true` if the value is strictly negative.
    def negative? : Bool
      @numerator.negative?
    end

    # Returns `true` if the denominator is 1 (i.e. the value is a whole number).
    def integer? : Bool
      @denominator == BigInt.new(1)
    end

    # --- Unary / misc ---

    # Returns the absolute value.
    def abs : BigRational
      BigRational.new(@numerator.abs, @denominator.clone)
    end

    # Returns the multiplicative inverse (reciprocal).
    #
    # Raises `DivisionByZeroError` if `self` is zero.
    def inv : BigRational
      raise DivisionByZeroError.new if @numerator.zero?
      BigRational.new(@denominator.clone, @numerator.clone)
    end

    # Returns the sign as -1, 0, or 1.
    @[AlwaysInline]
    def sign : Int32
      @numerator.sign
    end

    # Rounds toward negative infinity, returning an integer-valued rational.
    def floor : BigRational
      BigRational.new(@numerator // @denominator)
    end

    # Rounds toward positive infinity, returning an integer-valued rational.
    def ceil : BigRational
      BigRational.new(-(-@numerator // @denominator))
    end

    # Rounds toward zero (truncates), returning an integer-valued rational.
    def trunc : BigRational
      BigRational.new(@numerator.tdiv(@denominator))
    end

    # Rounds to the nearest integer, breaking ties away from zero.
    def round_away : BigRational
      rem2 = @numerator.remainder(@denominator).abs * BigInt.new(2)
      x = BigRational.new(@numerator.tdiv(@denominator))
      x += sign if rem2 >= @denominator
      x
    end

    # Rounds to the nearest integer, breaking ties to even (banker's rounding).
    def round_even : BigRational
      rem2 = @numerator.remainder(@denominator).abs * BigInt.new(2)
      x = BigRational.new(@numerator.tdiv(@denominator))
      x += sign if rem2 > @denominator || (rem2 == @denominator && x.numerator.odd?)
      x
    end

    # Divides by 2^*other* by scaling the denominator.
    def >>(other : Int) : BigRational
      BigRational.new(@numerator, @denominator * (BigInt.new(1) << other))
    end

    # Multiplies by 2^*other* by scaling the numerator.
    def <<(other : Int) : BigRational
      BigRational.new(@numerator * (BigInt.new(1) << other), @denominator.clone)
    end

    # --- Conversions ---

    # Converts to `Float64`. May lose precision for large values.
    def to_f64 : Float64
      @numerator.to_f64 / @denominator.to_f64
    end

    # Converts to `Float64` (alias for `#to_f64`).
    def to_f : Float64
      to_f64
    end

    # Converts to `Float32`. May lose precision.
    def to_f32 : Float32
      to_f64.to_f32
    end

    # Unchecked conversion to `Float32`.
    def to_f32! : Float32
      to_f64.to_f32
    end

    # Unchecked conversion to `Float64`.
    def to_f64! : Float64
      to_f64
    end

    # Unchecked conversion to `Float64`.
    def to_f! : Float64
      to_f64
    end

    # Truncates to `Int32`.
    def to_i : Int32
      to_i32
    end

    # Truncates to `Int8`.
    def to_i8 : Int8
      to_f64.to_i8
    end

    # Truncates to `Int16`.
    def to_i16 : Int16
      to_f64.to_i16
    end

    # Truncates to `Int32`.
    def to_i32 : Int32
      to_f64.to_i32
    end

    # Truncates to `Int64`.
    def to_i64 : Int64
      to_f64.to_i64
    end

    # Truncates to `UInt8`.
    def to_u8 : UInt8
      to_f64.to_u8
    end

    # Truncates to `UInt16`.
    def to_u16 : UInt16
      to_f64.to_u16
    end

    # Truncates to `UInt32`.
    def to_u32 : UInt32
      to_f64.to_u32
    end

    # Truncates to `UInt64`.
    def to_u64 : UInt64
      to_f64.to_u64
    end

    # Truncates the rational toward zero and returns a `BigInt`.
    def to_big_i : BigInt
      @numerator.tdiv(@denominator)
    end

    # Converts to a `BigFloat` with the given *precision* (in bits).
    def to_big_f(*, precision : Int32 = BigFloat.default_precision) : BigFloat
      BigFloat.new(@numerator, precision: precision) / BigFloat.new(@denominator, precision: precision)
    end

    # Returns the string representation. Integer-valued rationals omit the denominator.
    #
    # ```
    # BigNumber::BigRational.new(3, 4).to_s # => "3/4"
    # BigNumber::BigRational.new(6, 2).to_s # => "3"
    # ```
    def to_s : String
      String.build { |io| to_s(io) }
    end

    # Writes the string representation to the given *io*.
    def to_s(io : IO) : Nil
      if @denominator == BigInt.new(1)
        @numerator.to_s(io)
      else
        @numerator.to_s(io)
        io << '/'
        @denominator.to_s(io)
      end
    end

    # Returns the string representation in the given *base*.
    def to_s(base : Int) : String
      String.build { |io| to_s(io, base) }
    end

    # Writes the string representation in the given *base* to the given *io*.
    def to_s(io : IO, base : Int) : Nil
      if @denominator == BigInt.new(1)
        @numerator.to_s(io, base)
      else
        @numerator.to_s(io, base)
        io << '/'
        @denominator.to_s(io, base)
      end
    end

    # :ditto:
    def inspect(io : IO) : Nil
      to_s(io)
    end

    # Returns `self`.
    def to_big_r : BigRational
      self
    end

    # Converts to a `BigDecimal`.
    def to_big_d : BigDecimal
      BigDecimal.new(self)
    end

    # Computes a hash for this rational.
    def hash(hasher)
      hasher = @numerator.hash(hasher)
      hasher = @denominator.hash(hasher)
      hasher
    end

    # Returns a deep copy.
    def clone : BigRational
      BigRational.new(@numerator.clone, @denominator.clone)
    end

    # --- Private ---

    # Reduces the fraction to lowest terms and ensures a positive denominator.
    # Called automatically by constructors that accept separate numerator/denominator.
    private def canonicalize!
      raise DivisionByZeroError.new if @denominator.zero?

      # Handle zero numerator
      if @numerator.zero?
        @denominator = BigInt.new(1)
        return
      end

      g = @numerator.abs.gcd(@denominator.abs)
      unless g == BigInt.new(1)
        @numerator = @numerator // g
        @denominator = @denominator // g
      end

      # Ensure denominator is positive
      if @denominator.negative?
        @numerator = -@numerator
        @denominator = -@denominator
      end
    end
  end
end
