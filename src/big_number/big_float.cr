module BigNumber
  # Arbitrary-precision binary floating-point number with configurable precision.
  #
  # Internally represented as `sign * mantissa * 2^exponent`, where *mantissa* is a
  # `BigInt` normalized to exactly *precision* bits, *exponent* is an `Int64`, and
  # *sign* is -1, 0, or 1. The default precision is 128 bits.
  #
  # Unlike hardware floats, `BigFloat` never produces NaN or infinity -- it raises
  # on invalid operations instead.
  #
  # ```
  # a = BigNumber::BigFloat.new("3.14159", precision: 256)
  # b = BigNumber::BigFloat.new(2)
  # a / b # => 1.570795 (at 256-bit precision)
  # ```
  struct BigFloat
    include Comparable(BigFloat)
    include Comparable(Int)
    include Comparable(BigInt)

    # Returns the absolute value of the mantissa as a `BigInt`.
    getter mantissa : BigInt

    # Returns the binary exponent. The value equals `sign * mantissa * 2^exponent`.
    getter exponent : Int64

    # Returns the sign: -1, 0, or 1.
    getter sign : Int8

    # Returns the precision of this value in bits.
    getter precision : Int32

    # The default precision (in bits) used when none is specified. Initially 128.
    @@default_precision : Int32 = 128

    # Returns the current default precision in bits.
    def self.default_precision : Int32
      @@default_precision
    end

    # Sets the default precision in bits for newly created `BigFloat` values.
    #
    # Raises `ArgumentError` if *value* is not positive.
    def self.default_precision=(value : Int32)
      raise ArgumentError.new("Precision must be positive") unless value > 0
      @@default_precision = value
    end

    # --- Constructors ---

    # Creates a zero-valued `BigFloat` with the default precision.
    def initialize
      @mantissa = BigInt.new
      @exponent = 0_i64
      @sign = 0_i8
      @precision = @@default_precision
    end

    # Creates a zero-valued `BigFloat` with the given *precision* in bits.
    def initialize(*, precision : Int32)
      @mantissa = BigInt.new
      @exponent = 0_i64
      @sign = 0_i8
      @precision = precision
    end

    # Creates a `BigFloat` from an integer value.
    #
    # ```
    # BigNumber::BigFloat.new(42)                    # 128-bit precision
    # BigNumber::BigFloat.new(-7, precision: 256)    # 256-bit precision
    # ```
    def initialize(value : Int, *, precision : Int32 = @@default_precision)
      @precision = precision
      if value == 0
        @mantissa = BigInt.new
        @exponent = 0_i64
        @sign = 0_i8
      else
        @sign = value < 0 ? -1_i8 : 1_i8
        @mantissa = BigInt.new(value).abs
        @exponent = 0_i64
        normalize!
      end
    end

    # Creates a `BigFloat` from a `BigInt` value.
    def initialize(value : BigInt, *, precision : Int32 = @@default_precision)
      @precision = precision
      if value.zero?
        @mantissa = BigInt.new
        @exponent = 0_i64
        @sign = 0_i8
      else
        @sign = value.negative? ? -1_i8 : 1_i8
        @mantissa = value.abs
        @exponent = 0_i64
        normalize!
      end
    end

    # Creates a `BigFloat` from a `Float64`. Decomposes the IEEE 754 representation
    # exactly, then normalizes to the target precision.
    #
    # Raises `ArgumentError` for non-finite floats (NaN, infinity).
    #
    # ```
    # BigNumber::BigFloat.new(0.1) # exact binary approximation of 0.1
    # ```
    def initialize(value : Float64, *, precision : Int32 = @@default_precision)
      raise ArgumentError.new("Non-finite float") unless value.finite?
      @precision = precision
      if value == 0.0
        @mantissa = BigInt.new
        @exponent = 0_i64
        @sign = 0_i8
        return
      end

      @sign = value < 0 ? -1_i8 : 1_i8

      # Decompose Float64: value = (-1)^s * mantissa * 2^(exp - 1023 - 52)
      bits = value.unsafe_as(UInt64)
      biased_exp = ((bits >> 52) & 0x7FF).to_i64
      frac = bits & 0x000FFFFFFFFFFFFF_u64

      if biased_exp == 0
        # Subnormal: no implicit leading 1
        @mantissa = BigInt.new(frac)
        @exponent = 1_i64 - 1023_i64 - 52_i64
      else
        @mantissa = BigInt.new(frac | 0x0010000000000000_u64)
        @exponent = biased_exp - 1023_i64 - 52_i64
      end

      normalize!
    end

    # Creates a `BigFloat` from a `Float32` by promoting to `Float64`.
    def initialize(value : Float32, *, precision : Int32 = @@default_precision)
      initialize(value.to_f64, precision: precision)
    end

    # Creates a `BigFloat` from a `BigRational` by dividing numerator by denominator
    # with enough precision for rounding.
    def initialize(value : BigRational, *, precision : Int32 = @@default_precision)
      @precision = precision
      if value.zero?
        @mantissa = BigInt.new
        @exponent = 0_i64
        @sign = 0_i8
        return
      end

      @sign = value.negative? ? -1_i8 : 1_i8
      num = value.numerator.abs
      den = value.denominator

      # We want precision bits of quotient
      # Shift numerator left enough so that quotient has at least precision+2 bits for rounding
      num_bits = num.bit_length
      den_bits = den.bit_length
      shift = @precision + 2 - (num_bits - den_bits)
      shift = 0 if shift < 0

      shifted_num = num << shift
      q, r = shifted_num.tdiv_rem(den)

      @mantissa = q
      @exponent = -shift.to_i64

      # Round using remainder
      round_using_remainder!(r, den)
      normalize!
    end

    # Parses a `BigFloat` from a decimal string. Supports optional sign, decimal point,
    # and scientific notation (e.g. `"1.5e10"`, `"-0.001"`, `"42"`).
    #
    # Raises `ArgumentError` for empty strings.
    #
    # ```
    # BigNumber::BigFloat.new("3.14159265358979323846") # parsed at default precision
    # BigNumber::BigFloat.new("1e-100", precision: 512) # scientific notation
    # ```
    def initialize(str : String, *, precision : Int32 = @@default_precision)
      @precision = precision
      s = str.strip

      if s.empty?
        raise ArgumentError.new("Invalid BigFloat string: empty")
      end

      # Parse sign
      neg = false
      if s[0] == '-'
        neg = true
        s = s[1..]
      elsif s[0] == '+'
        s = s[1..]
      end

      # Split on 'e' or 'E' for exponent
      dec_exp = 0_i64
      if (e_pos = s.index('e') || s.index('E'))
        exp_str = s[(e_pos + 1)..]
        s = s[0...e_pos]
        dec_exp = exp_str.to_i64
      end

      # Split on '.' for fractional part
      int_str = ""
      frac_str = ""
      if (dot_pos = s.index('.'))
        int_str = s[0...dot_pos]
        frac_str = s[(dot_pos + 1)..]
      else
        int_str = s
      end

      int_str = "0" if int_str.empty?
      frac_str = "0" if frac_str.empty?

      # Combine integer and fractional parts: value = (int_str + frac_str) * 10^(dec_exp - frac_len)
      combined = BigInt.new(int_str + frac_str)
      total_dec_exp = dec_exp - frac_str.size.to_i64

      if combined.zero?
        @mantissa = BigInt.new
        @exponent = 0_i64
        @sign = 0_i8
        return
      end

      @sign = neg ? -1_i8 : 1_i8

      # Convert: combined * 10^total_dec_exp to binary float
      # = combined * 5^total_dec_exp * 2^total_dec_exp
      if total_dec_exp >= 0
        # Multiply by 10^total_dec_exp = 5^total_dec_exp * 2^total_dec_exp
        factor = BigInt.new(5) ** total_dec_exp.to_i32
        @mantissa = combined * factor
        @exponent = total_dec_exp
        normalize!
      else
        # Divide by 10^(-total_dec_exp)
        # value = combined / 5^(-total_dec_exp) * 2^total_dec_exp
        # We need to do a division with enough precision
        divisor = BigInt.new(5) ** (-total_dec_exp).to_i32
        num_bits = combined.bit_length
        den_bits = divisor.bit_length
        shift = @precision + 2 - (num_bits - den_bits)
        shift = 0 if shift < 0

        shifted = combined << shift
        q, r = shifted.tdiv_rem(divisor)

        @mantissa = q
        @exponent = total_dec_exp - shift.to_i64

        round_using_remainder!(r, divisor)
        normalize!
      end
    end

    # Creates a copy of another `BigFloat`.
    def initialize(other : BigFloat)
      @mantissa = other.mantissa.clone
      @exponent = other.exponent
      @sign = other.sign
      @precision = other.precision
    end

    # Internal constructor from raw components. Does not normalize.
    protected def initialize(@mantissa : BigInt, @exponent : Int64, @sign : Int8, @precision : Int32)
    end

    # Returns a deep copy.
    def clone : BigFloat
      BigFloat.new(self)
    end

    # --- Predicates ---

    # Returns `true` if the value is zero.
    def zero? : Bool
      @sign == 0
    end

    # Returns `true` if the value is strictly positive.
    def positive? : Bool
      @sign > 0
    end

    # Returns `true` if the value is strictly negative.
    def negative? : Bool
      @sign < 0
    end

    # Always returns `false`. `BigFloat` cannot represent NaN.
    @[AlwaysInline]
    def nan? : Bool
      false
    end

    # Always returns `nil`. `BigFloat` cannot represent infinity.
    @[AlwaysInline]
    def infinite? : Int32?
      nil
    end

    # Returns `true` if the value has no fractional part.
    def integer? : Bool
      return true if zero?
      return true if @exponent >= 0
      frac_bits = (-@exponent).to_i32
      bit_len = @mantissa.bit_length
      return true if frac_bits >= bit_len # mantissa is entirely fractional but zero? already handled
      # Check if all fractional bits are zero
      mask = (BigInt.new(1) << frac_bits) - BigInt.new(1)
      (@mantissa & mask) == BigInt.new(0)
    end

    # --- Comparison ---

    # Compares `self` with *other* by sign, then by magnitude alignment.
    def <=>(other : BigFloat) : Int32
      # Different signs
      return 0 if @sign == 0 && other.sign == 0
      return @sign.to_i32 if @sign != other.sign

      # Same sign - compare magnitudes, negate if negative
      cmp = compare_magnitude(other)
      @sign < 0 ? -cmp : cmp
    end

    # :ditto:
    def <=>(other : Int) : Int32
      self <=> BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def <=>(other : BigInt) : Int32
      self <=> BigFloat.new(other, precision: @precision)
    end

    # Compares with a primitive float. Returns `nil` for NaN.
    def <=>(other : Float) : Int32?
      return nil if other.nan?
      self <=> BigFloat.new(other.to_f64, precision: @precision)
    end

    # Returns `true` if `self` and *other* represent the same value.
    def ==(other : BigFloat) : Bool
      return true if @sign == 0 && other.sign == 0
      return false if @sign != other.sign
      # Compare by value: align mantissas
      (self <=> other) == 0
    end

    # :ditto:
    def ==(other : Int) : Bool
      self == BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def ==(other : BigInt) : Bool
      self == BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def ==(other : Float) : Bool
      return false if other.nan?
      self == BigFloat.new(other.to_f64, precision: @precision)
    end

    # Computes a hash for this value.
    def hash(hasher)
      hasher = @sign.hash(hasher)
      hasher = @mantissa.hash(hasher)
      hasher = @exponent.hash(hasher)
      hasher
    end

    # --- Unary ---

    # Returns the negation of `self`.
    def - : BigFloat
      return clone if zero?
      BigFloat.new(@mantissa.clone, @exponent, (-@sign).to_i8, @precision)
    end

    # Returns the absolute value.
    def abs : BigFloat
      return clone if zero?
      BigFloat.new(@mantissa.clone, @exponent, 1_i8, @precision)
    end

    # --- Arithmetic ---

    # Returns the sum of `self` and *other*. The result precision is the
    # maximum of both operands' precisions.
    def +(other : BigFloat) : BigFloat
      return other.clone if zero?
      return clone if other.zero?

      result_precision = Math.max(@precision, other.precision)

      # Align exponents: shift the one with larger exponent left
      exp_diff = @exponent - other.exponent

      if exp_diff >= 0
        # self has larger exponent, shift self's mantissa left
        a = @mantissa << exp_diff.to_i32
        b = other.mantissa
        result_exp = other.exponent
      else
        a = @mantissa
        b = other.mantissa << (-exp_diff).to_i32
        result_exp = @exponent
      end

      # Add or subtract based on signs
      if @sign == other.sign
        result_mantissa = a + b
        result_sign = @sign
      else
        cmp = a <=> b
        if cmp > 0
          result_mantissa = a - b
          result_sign = @sign
        elsif cmp < 0
          result_mantissa = b - a
          result_sign = other.sign
        else
          return BigFloat.new(precision: result_precision)
        end
      end

      result = BigFloat.new(result_mantissa, result_exp, result_sign, result_precision)
      result.normalize!
      result
    end

    # :ditto:
    def +(other : Int) : BigFloat
      self + BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def +(other : BigInt) : BigFloat
      self + BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def +(other : Float) : BigFloat
      self + BigFloat.new(other.to_f64, precision: @precision)
    end

    # Returns the difference of `self` and *other*.
    def -(other : BigFloat) : BigFloat
      self + (-other)
    end

    # :ditto:
    def -(other : Int) : BigFloat
      self - BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def -(other : BigInt) : BigFloat
      self - BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def -(other : Float) : BigFloat
      self - BigFloat.new(other.to_f64, precision: @precision)
    end

    # Returns the product of `self` and *other*.
    def *(other : BigFloat) : BigFloat
      return BigFloat.new(precision: Math.max(@precision, other.precision)) if zero? || other.zero?

      result_precision = Math.max(@precision, other.precision)
      result_mantissa = @mantissa * other.mantissa
      result_exponent = @exponent + other.exponent
      result_sign = (@sign * other.sign).to_i8

      result = BigFloat.new(result_mantissa, result_exponent, result_sign, result_precision)
      result.normalize!
      result
    end

    # :ditto:
    def *(other : Int) : BigFloat
      self * BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def *(other : BigInt) : BigFloat
      self * BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def *(other : Float) : BigFloat
      self * BigFloat.new(other.to_f64, precision: @precision)
    end

    # Returns the quotient of `self` divided by *other*.
    #
    # Raises `DivisionByZeroError` if *other* is zero.
    def /(other : BigFloat) : BigFloat
      raise DivisionByZeroError.new if other.zero?
      return BigFloat.new(precision: Math.max(@precision, other.precision)) if zero?

      result_precision = Math.max(@precision, other.precision)

      # Shift dividend left by precision bits to get enough quotient bits
      shift = result_precision + 2
      shifted = @mantissa << shift
      q, r = shifted.tdiv_rem(other.mantissa)

      result_exponent = @exponent - other.exponent - shift.to_i64
      result_sign = (@sign * other.sign).to_i8

      result = BigFloat.new(q, result_exponent, result_sign, result_precision)
      result.round_using_remainder!(r, other.mantissa)
      result.normalize!
      result
    end

    # :ditto:
    def /(other : Int) : BigFloat
      self / BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def /(other : BigInt) : BigFloat
      self / BigFloat.new(other, precision: @precision)
    end

    # :ditto:
    def /(other : Float) : BigFloat
      self / BigFloat.new(other.to_f64, precision: @precision)
    end

    # Raises `self` to the given integer *exp* using binary exponentiation.
    # Negative exponents compute the reciprocal.
    def **(exp : Int) : BigFloat
      return BigFloat.new(1, precision: @precision) if exp == 0
      if exp < 0
        return BigFloat.new(1, precision: @precision) / (self ** (-exp))
      end
      if exp == 1
        return clone
      end

      # Binary exponentiation
      result = BigFloat.new(1, precision: @precision)
      base = clone
      e = exp
      while e > 0
        result = result * base if e.odd?
        base = base * base
        e >>= 1
      end
      result
    end

    # Raises `self` to the given `BigInt` *exp* using binary exponentiation.
    def **(exp : BigInt) : BigFloat
      return BigFloat.new(1, precision: @precision) if exp.zero?
      if exp.negative?
        return BigFloat.new(1, precision: @precision) / (self ** (-exp))
      end
      # Binary exponentiation
      result = BigFloat.new(1, precision: @precision)
      base = clone
      e = exp.clone
      one = BigInt.new(1)
      while e > BigInt.new(0)
        result = result * base if e.odd?
        base = base * base
        e = e >> 1
      end
      result
    end

    # --- Rounding ---

    # Rounds toward negative infinity, returning an integer-valued `BigFloat`.
    def floor : BigFloat
      return clone if zero?

      # If the value is purely integer (all bits above the binary point), return as-is
      # The value is mantissa * 2^exponent
      # Number of bits in mantissa = bit_length
      # If exponent >= 0, value is integer
      bit_len = @mantissa.bit_length
      if @exponent >= 0
        return clone
      end

      # fractional_bits = -exponent
      frac_bits = (-@exponent).to_i32

      if frac_bits >= bit_len
        # |value| < 1
        return negative? ? BigFloat.new(-1, precision: @precision) : BigFloat.new(precision: @precision)
      end

      # Mask off fractional bits
      integer_mantissa = @mantissa >> frac_bits

      if negative?
        # Check if there were any fractional bits set
        mask = (BigInt.new(1) << frac_bits) - BigInt.new(1)
        has_frac = (@mantissa & mask) != BigInt.new(0)
        integer_mantissa = integer_mantissa + BigInt.new(1) if has_frac
      end

      if integer_mantissa.zero?
        return BigFloat.new(precision: @precision)
      end

      result = BigFloat.new(integer_mantissa, 0_i64, @sign, @precision)
      result.normalize!
      result
    end

    # Rounds toward positive infinity, returning an integer-valued `BigFloat`.
    def ceil : BigFloat
      -((-self).floor)
    end

    # Rounds toward zero (truncates), returning an integer-valued `BigFloat`.
    def trunc : BigFloat
      negative? ? ceil : floor
    end

    # Rounds to the nearest integer using round-half-to-even (banker's rounding).
    def round : BigFloat
      return clone if zero?

      if @exponent >= 0
        return clone
      end

      frac_bits = (-@exponent).to_i32
      bit_len = @mantissa.bit_length

      if frac_bits > bit_len
        return BigFloat.new(precision: @precision)
      end

      if frac_bits == 0
        return clone
      end

      # Get the integer part
      integer_mantissa = @mantissa >> frac_bits

      # Check the top fractional bit (0.5 position)
      if frac_bits >= 1
        half_bit = @mantissa.bit(frac_bits - 1)
        if half_bit == 1
          # Check remaining fractional bits for ties
          if frac_bits >= 2
            mask = (BigInt.new(1) << (frac_bits - 1)) - BigInt.new(1)
            remaining = @mantissa & mask
            if remaining.zero?
              # Exact tie - round to even
              integer_mantissa = integer_mantissa + BigInt.new(1) if integer_mantissa.odd?
            else
              # Above half - round up (away from zero in magnitude)
              integer_mantissa = integer_mantissa + BigInt.new(1)
            end
          else
            # Only the half bit, exact tie - round to even
            integer_mantissa = integer_mantissa + BigInt.new(1) if integer_mantissa.odd?
          end
        end
        # Below half - truncate (already done)
      end

      if integer_mantissa.zero?
        return BigFloat.new(precision: @precision)
      end

      result = BigFloat.new(integer_mantissa, 0_i64, @sign, @precision)
      result.normalize!
      result
    end

    # Rounds to the nearest integer, breaking ties away from zero.
    def round_away : BigFloat
      if positive?
        (self + BigFloat.new(0.5, precision: @precision)).floor
      elsif negative?
        (self - BigFloat.new(0.5, precision: @precision)).ceil
      else
        clone
      end
    end

    # Rounds to the nearest integer, breaking ties to even (banker's rounding).
    def round_even : BigFloat
      return clone if zero?
      if positive?
        halfway = self + BigFloat.new(0.5, precision: @precision)
      else
        halfway = self - BigFloat.new(0.5, precision: @precision)
      end
      if halfway.integer?
        # Check if halfway is even
        hw_int = halfway.to_big_i
        if hw_int.even?
          halfway
        else
          halfway - BigFloat.new(sign.to_i32, precision: @precision)
        end
      else
        halfway.trunc == self.trunc ? self.trunc : (positive? ? halfway.floor : halfway.ceil)
      end
    end

    # --- Conversions ---

    # Converts to `Float64`. May lose precision or overflow to infinity.
    def to_f64 : Float64
      return 0.0 if zero?

      # The value is sign * mantissa * 2^exponent
      # Float64 has 53-bit mantissa, exponent range -1022..1023
      bit_len = @mantissa.bit_length

      # Effective exponent of the top bit
      top_exp = @exponent.to_i64 + bit_len.to_i64 - 1

      # Check overflow
      if top_exp > 1023
        return @sign > 0 ? Float64::INFINITY : -Float64::INFINITY
      end

      # Check underflow
      if top_exp < -1074
        return @sign > 0 ? 0.0 : -0.0
      end

      # Extract top 53 bits
      if bit_len <= 53
        mantissa_val = @mantissa.to_u64
        mantissa_val <<= (53 - bit_len)
        result_exp = @exponent.to_i64 - (53 - bit_len).to_i64
      else
        shift = bit_len - 53
        mantissa_val = (@mantissa >> shift).to_u64
        result_exp = @exponent.to_i64 + shift.to_i64

        # Round
        if shift >= 1 && @mantissa.bit(shift - 1) == 1
          # Check sticky bits
          if shift >= 2
            mask = (BigInt.new(1) << (shift - 1)) - BigInt.new(1)
            sticky = (@mantissa & mask) != BigInt.new(0)
            if sticky
              mantissa_val += 1
            else
              # Ties to even
              mantissa_val += 1 if mantissa_val.odd?
            end
          else
            mantissa_val += 1 if mantissa_val.odd?
          end

          # Handle mantissa overflow after rounding
          if mantissa_val >= (1_u64 << 53)
            mantissa_val >>= 1
            result_exp += 1
          end
        end
      end

      # Construct Float64 from parts
      biased_exp = result_exp + 1023 + 52

      if biased_exp >= 2047
        return @sign > 0 ? Float64::INFINITY : -Float64::INFINITY
      end

      if biased_exp <= 0
        # Subnormal
        shift_amount = 1 - biased_exp
        if shift_amount >= 64
          return @sign > 0 ? 0.0 : -0.0
        end
        mantissa_val >>= shift_amount
        biased_exp = 0_i64
      end

      # Remove implicit leading 1 bit
      mantissa_val &= 0x000FFFFFFFFFFFFF_u64

      bits = mantissa_val
      bits |= (biased_exp.to_u64 << 52)
      bits |= (1_u64 << 63) if @sign < 0

      bits.unsafe_as(Float64)
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
      to_f64.to_f32!
    end

    # Unchecked conversion to `Float64`.
    def to_f64! : Float64
      to_f64
    end

    # Unchecked conversion to `Float64`.
    def to_f! : Float64
      to_f64
    end

    # Returns the sign as an `Int32` (-1, 0, or 1).
    def sign_i32 : Int32
      @sign.to_i32
    end

    # Truncates to `Int32`.
    def to_i : Int32
      to_i32
    end

    # Unchecked truncation to `Int32`.
    def to_i! : Int32
      to_i32!
    end

    # Truncates to `UInt32`.
    def to_u : UInt32
      to_u32
    end

    # Unchecked truncation to `UInt32`.
    def to_u! : UInt32
      to_u32!
    end

    {% for info in [{Int8, "i8"}, {Int16, "i16"}, {Int32, "i32"}, {Int64, "i64"}] %}
      # Truncates to `{{info[0]}}`.
      def to_{{info[1].id}} : {{info[0]}}
        to_big_i.to_{{info[1].id}}
      end

      # Unchecked truncation to `{{info[0]}}`.
      def to_{{info[1].id}}! : {{info[0]}}
        to_big_i.to_{{info[1].id}}!
      end
    {% end %}

    {% for info in [{UInt8, "u8"}, {UInt16, "u16"}, {UInt32, "u32"}, {UInt64, "u64"}] %}
      # Truncates to `{{info[0]}}`.
      def to_{{info[1].id}} : {{info[0]}}
        to_big_i.to_{{info[1].id}}
      end

      # Unchecked truncation to `{{info[0]}}`.
      def to_{{info[1].id}}! : {{info[0]}}
        to_big_i.to_{{info[1].id}}!
      end
    {% end %}

    # Truncates the value toward zero and returns a `BigInt`.
    def to_big_i : BigInt
      return BigInt.new if zero?

      bit_len = @mantissa.bit_length

      if @exponent >= 0
        result = @mantissa << @exponent.to_i32
      elsif (-@exponent) >= bit_len
        return BigInt.new
      else
        result = @mantissa >> (-@exponent).to_i32
      end

      @sign < 0 ? -result : result
    end

    # Converts to an exact `BigRational` (mantissa * 2^exponent as a fraction).
    def to_big_r : BigRational
      return BigRational.new(0) if zero?

      signed_mantissa = @sign < 0 ? -@mantissa : @mantissa.clone

      if @exponent >= 0
        BigRational.new(signed_mantissa << @exponent.to_i32)
      else
        BigRational.new(signed_mantissa, BigInt.new(1) << (-@exponent).to_i32)
      end
    end

    # Returns the decimal string representation with approximately
    # `precision * log10(2)` significant digits.
    #
    # ```
    # BigNumber::BigFloat.new(3).to_s  # => "3.0"
    # BigNumber::BigFloat.new(-1, 2).to_s # => "-0.5"
    # ```
    def to_s : String
      String.build { |io| to_s(io) }
    end

    # Writes the decimal string representation to the given *io*.
    def to_s(io : IO) : Nil
      if zero?
        io << "0.0"
        return
      end

      io << '-' if negative?

      # Convert to rational and then to decimal string
      rat = to_big_r.abs

      integer_part, remainder = rat.numerator.tdiv_rem(rat.denominator)
      io << integer_part.to_s
      io << '.'

      if remainder.zero?
        io << '0'
        return
      end

      # Generate decimal digits
      # Number of significant decimal digits ≈ precision * log10(2) ≈ precision * 0.301
      max_digits = (@precision * 301 // 1000) + 1
      max_digits = 1 if max_digits < 1

      digits = String.build do |buf|
        r = remainder
        max_digits.times do
          r = r * BigInt.new(10)
          d, r = r.tdiv_rem(rat.denominator)
          buf << d.to_s
          break if r.zero?
        end
      end

      # Strip trailing zeros but keep at least one digit
      stripped = digits.rstrip('0')
      stripped = "0" if stripped.empty?
      io << stripped
    end

    # :ditto:
    def inspect(io : IO) : Nil
      to_s(io)
    end

    # Returns `self`.
    def to_big_f : BigFloat
      self
    end

    # --- Internal ---

    # Normalizes the mantissa to exactly `@precision` bits by shifting left or right,
    # adjusting the exponent accordingly. Applies round-to-nearest-even when truncating.
    protected def normalize!
      if @mantissa.zero?
        @sign = 0_i8
        @exponent = 0_i64
        return
      end

      bit_len = @mantissa.bit_length

      if bit_len > @precision
        # Need to shift right (losing bits) and round
        shift = bit_len - @precision
        round_bit_shift!(shift)
      elsif bit_len < @precision
        # Shift left to fill precision
        shift = @precision - bit_len
        @mantissa = @mantissa << shift
        @exponent -= shift.to_i64
      end
      # bit_len == @precision: already normalized
    end

    # Rounds the mantissa based on a division remainder using round-to-nearest-even.
    protected def round_using_remainder!(r : BigInt, divisor : BigInt)
      return if r.zero?

      # Check if remainder > divisor/2 (round up)
      # 2*r > divisor  =>  round up
      # 2*r == divisor =>  round to even
      # 2*r < divisor  =>  round down (nothing to do)
      doubled = r << 1
      cmp = doubled <=> divisor
      if cmp > 0
        @mantissa = @mantissa + BigInt.new(1)
      elsif cmp == 0
        # Tie: round to even
        @mantissa = @mantissa + BigInt.new(1) if @mantissa.odd?
      end
    end

    private def round_bit_shift!(shift : Int32)
      return if shift <= 0

      # Guard bit (top bit being shifted out)
      guard = @mantissa.bit(shift - 1)

      # Sticky bits (any bit below guard)
      sticky = if shift >= 2
                  mask = (BigInt.new(1) << (shift - 1)) - BigInt.new(1)
                  (@mantissa & mask) != BigInt.new(0)
                else
                  false
                end

      @mantissa = @mantissa >> shift
      @exponent += shift.to_i64

      # Round to nearest even
      if guard == 1
        if sticky
          @mantissa = @mantissa + BigInt.new(1)
        else
          # Exact tie: round to even
          @mantissa = @mantissa + BigInt.new(1) if @mantissa.odd?
        end
      end

      # After rounding, mantissa might have grown by 1 bit
      if @mantissa.bit_length > @precision
        @mantissa = @mantissa >> 1
        @exponent += 1_i64
      end
    end

    private def compare_magnitude(other : BigFloat) : Int32
      # Compare |self| vs |other|
      # value = mantissa * 2^exponent, mantissa is normalized to precision bits
      # So top bit position = exponent + precision - 1
      self_top = @exponent.to_i64 + @mantissa.bit_length.to_i64 - 1
      other_top = other.exponent.to_i64 + other.mantissa.bit_length.to_i64 - 1

      return 1 if self_top > other_top
      return -1 if self_top < other_top

      # Same top bit position, need to align and compare mantissas
      exp_diff = @exponent - other.exponent
      if exp_diff >= 0
        a = @mantissa << exp_diff.to_i32
        b = other.mantissa
      else
        a = @mantissa
        b = other.mantissa << (-exp_diff).to_i32
      end
      a <=> b
    end
  end
end
