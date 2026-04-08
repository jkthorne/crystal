module BigNumber
  # Raised when a `BigDecimal` cannot be parsed from a string.
  #
  # ```
  # BigNumber::BigDecimal.new("not_a_number") # raises InvalidBigDecimalException
  # ```
  class InvalidBigDecimalException < Exception
    def initialize(big_decimal_str : String, reason : String)
      super("Invalid BigDecimal: #{big_decimal_str} (#{reason})")
    end
  end

  # Arbitrary-precision decimal arithmetic with fixed scale.
  #
  # A `BigDecimal` is represented as a `BigInt` *value* and a `UInt64` *scale*,
  # where the numeric value equals `value * 10^(-scale)`. This avoids the
  # rounding errors inherent in binary floating-point representations.
  #
  # ```
  # d = BigNumber::BigDecimal.new("123.456")
  # d.value # => BigInt(123456)
  # d.scale # => 3
  # d + BigNumber::BigDecimal.new("0.544") # => 124.0
  # ```
  struct BigDecimal
    include Comparable(BigDecimal)
    include Comparable(Int)
    include Comparable(Float)
    include Comparable(BigRational)

    private TWO  = 2
    private FIVE = 5
    private TEN  = 10

    private TWO_I  = BigInt.new(2)
    private FIVE_I = BigInt.new(5)
    private TEN_I  = BigInt.new(10)

    # Default precision (number of decimal digits) used for division.
    DEFAULT_PRECISION = 100_u64

    # Returns the unscaled `BigInt` value. The decimal value is `value * 10^(-scale)`.
    getter value : BigInt

    # Returns the scale (number of decimal digits after the point).
    getter scale : UInt64

    # Creates a new `BigDecimal` from `Float`.
    def self.new(num : Float) : self
      raise ArgumentError.new "Can only construct from a finite number" unless num.finite?
      new(num.to_s)
    end

    # Creates a new `BigDecimal` from `BigRational`.
    def self.new(num : BigRational) : self
      num.numerator.to_big_d / num.denominator.to_big_d
    end

    # Returns *num*.
    def self.new(num : BigDecimal) : self
      num
    end

    # Creates a new `BigDecimal` from `BigInt` *value* and `UInt64` *scale*.
    def initialize(@value : BigInt, @scale : UInt64)
    end

    # Creates a new `BigDecimal` from `Int`.
    def initialize(num : Int = 0, scale : Int = 0)
      @value = BigInt.new(num)
      @scale = scale.to_u64
    end

    # Creates a new `BigDecimal` from `BigInt`.
    def initialize(num : BigInt, scale : Int = 0)
      @value = num
      @scale = scale.to_u64
    end

    # Creates a new `BigDecimal` from a `String`.
    #
    # Supports optional sign, decimal point, underscores, and scientific notation.
    #
    # ```
    # BigNumber::BigDecimal.new("1.5e2") # => 150.0
    # BigNumber::BigDecimal.new("-0.01") # => -0.01
    # ```
    def initialize(str : String)
      str = str.lchop('+')
      str = str.delete('_')

      raise InvalidBigDecimalException.new(str, "Zero size") if str.bytesize == 0

      decimal_index = nil
      exponent_index = nil
      input_length = str.bytesize

      str.each_char_with_index do |char, index|
        final_character = index == input_length - 1
        first_character = index == 0
        case char
        when '-'
          unless (first_character && !final_character) || (exponent_index == index - 1 && !final_character)
            raise InvalidBigDecimalException.new(str, "Unexpected '-' character")
          end
        when '+'
          if final_character || exponent_index != index - 1
            raise InvalidBigDecimalException.new(str, "Unexpected '+' character")
          end
        when '.'
          if decimal_index || exponent_index
            raise InvalidBigDecimalException.new(str, "Unexpected '.' character")
          end
          decimal_index = index
        when 'e', 'E'
          if first_character || final_character || exponent_index || decimal_index == index - 1
            raise InvalidBigDecimalException.new(str, "Unexpected #{char.inspect} character")
          end
          exponent_index = index
        when '0'..'9'
          # Pass
        else
          raise InvalidBigDecimalException.new(str, "Unexpected #{char.inspect} character")
        end
      end

      decimal_end_index = (exponent_index || input_length) - 1
      if decimal_index
        decimal_count = (decimal_end_index - decimal_index).to_u64

        value_str = String.build do |builder|
          builder.write(str.to_slice[0, decimal_index])
          builder.write(str.to_slice[decimal_index + 1, decimal_count])
        end
        @value = BigInt.new(value_str)
      else
        decimal_count = 0_u64
        @value = BigInt.new(str[0..decimal_end_index])
      end

      if exponent_index
        exponent_postfix = str[exponent_index + 1]
        case exponent_postfix
        when '+', '-'
          exponent_positive = exponent_postfix == '+'
          exponent = str[(exponent_index + 2)..-1].to_u64
        else
          exponent_positive = true
          exponent = str[(exponent_index + 1)..-1].to_u64
        end

        @scale = exponent
        if exponent_positive
          if @scale < decimal_count
            @scale = decimal_count - @scale
          else
            @scale -= decimal_count
            @value = @value * (TEN_I ** @scale)
            @scale = 0_u64
          end
        else
          @scale += decimal_count
        end
      else
        @scale = decimal_count
      end
    end

    # --- Arithmetic ---

    # Returns the negation of this decimal.
    def - : BigDecimal
      BigDecimal.new(-@value, @scale)
    end

    # Returns the sum of `self` and *other*.
    def +(other : BigDecimal) : BigDecimal
      if @scale > other.scale
        scaled = other.scale_to(self)
        BigDecimal.new(@value + scaled.value, @scale)
      elsif @scale < other.scale
        scaled = scale_to(other)
        BigDecimal.new(scaled.value + other.value, other.scale)
      else
        BigDecimal.new(@value + other.value, @scale)
      end
    end

    # Returns the sum of `self` and *other*.
    def +(other : Int) : BigDecimal
      self + BigDecimal.new(other)
    end

    # Returns the sum of `self` and *other*.
    def +(other : BigInt) : BigDecimal
      self + BigDecimal.new(other)
    end

    # Returns the difference of `self` and *other*.
    def -(other : BigDecimal) : BigDecimal
      if @scale > other.scale
        scaled = other.scale_to(self)
        BigDecimal.new(@value - scaled.value, @scale)
      elsif @scale < other.scale
        scaled = scale_to(other)
        BigDecimal.new(scaled.value - other.value, other.scale)
      else
        BigDecimal.new(@value - other.value, @scale)
      end
    end

    # Returns the difference of `self` and *other*.
    def -(other : Int) : BigDecimal
      self - BigDecimal.new(other)
    end

    # Returns the difference of `self` and *other*.
    def -(other : BigInt) : BigDecimal
      self - BigDecimal.new(other)
    end

    # Returns the product of `self` and *other*.
    def *(other : BigDecimal) : BigDecimal
      BigDecimal.new(@value * other.value, @scale + other.scale)
    end

    # Returns the product of `self` and *other*.
    def *(other : Int) : BigDecimal
      self * BigDecimal.new(other)
    end

    # Returns the product of `self` and *other*.
    def *(other : BigInt) : BigDecimal
      self * BigDecimal.new(other)
    end

    # Returns the remainder of `self` divided by *other*.
    def %(other : BigDecimal) : BigDecimal
      if @scale > other.scale
        scaled = other.scale_to(self)
        BigDecimal.new(@value % scaled.value, @scale)
      elsif @scale < other.scale
        scaled = scale_to(other)
        BigDecimal.new(scaled.value % other.value, other.scale)
      else
        BigDecimal.new(@value % other.value, @scale)
      end
    end

    # Returns the remainder of `self` divided by *other*.
    def %(other : Int) : BigDecimal
      self % BigDecimal.new(other)
    end

    # Returns the quotient of `self` divided by *other* using `DEFAULT_PRECISION`.
    def /(other : BigDecimal) : BigDecimal
      div other
    end

    # Returns the quotient of `self` divided by *other*.
    def /(other : Int) : BigDecimal
      self / BigDecimal.new(other)
    end

    # Returns the quotient of `self` divided by *other*.
    def /(other : BigInt) : BigDecimal
      self / BigDecimal.new(other)
    end

    # Divides `self` by *other* with the given decimal digit *precision*.
    #
    # For exact divisions (e.g. dividing by powers of 2 and 5), the result
    # may use fewer digits than *precision*. For non-terminating decimals,
    # the result is truncated to *precision* digits.
    #
    # ```
    # BigNumber::BigDecimal.new(1).div(BigNumber::BigDecimal.new(3), 10)
    # # => 0.3333333333
    # ```
    def div(other : BigDecimal, precision : Int = DEFAULT_PRECISION) : BigDecimal
      check_division_by_zero other
      return self if @value.zero?
      other.factor_powers_of_ten

      numerator, denominator = @value, other.@value
      scale = if @scale >= other.scale
                @scale - other.scale
              else
                numerator = numerator * power_ten_to(other.scale - @scale)
                0_u64
              end

      quotient, remainder = numerator.divmod(denominator)
      if remainder.zero?
        return BigDecimal.new(normalize_quotient(other, quotient), scale)
      end

      denominator_reduced, denominator_exp2 = denominator.factor_by(TWO)

      case denominator_reduced
      when BigInt.new(1)
        denominator_exp5 = 0_u64
      when BigInt.new(5)
        denominator_reduced = denominator_reduced // FIVE_I
        denominator_exp5 = 1_u64
      when BigInt.new(25)
        denominator_reduced = denominator_reduced // FIVE_I // FIVE_I
        denominator_exp5 = 2_u64
      else
        denominator_reduced, denominator_exp5 = denominator_reduced.factor_by(FIVE)
      end

      if denominator_reduced != BigInt.new(1)
        scale_add = precision.to_u64
      elsif denominator_exp2 <= 1 && denominator_exp5 <= 1
        quotient = numerator * TEN_I // denominator
        return BigDecimal.new(normalize_quotient(other, quotient), scale + 1)
      else
        _, numerator_exp10 = remainder.factor_by(TEN)
        scale_add = {denominator_exp2, denominator_exp5}.max - numerator_exp10
        scale_add = precision.to_u64 if scale_add > precision
      end

      quotient = numerator * power_ten_to(scale_add) // denominator
      BigDecimal.new(normalize_quotient(other, quotient), scale + scale_add)
    end

    # Returns `self` raised to the power *other*.
    # Negative exponents convert through `BigRational`.
    def **(other : Int) : BigDecimal
      return (to_big_r ** other).to_big_d if other < 0
      BigDecimal.new(@value ** other, @scale * other)
    end

    # --- Comparison ---

    # Compares `self` with *other*. Returns -1, 0, or 1.
    def <=>(other : BigDecimal) : Int32
      if @scale > other.scale
        @value <=> other.scale_to(self).value
      elsif @scale < other.scale
        scale_to(other).value <=> other.value
      else
        @value <=> other.value
      end
    end

    # Compares `self` with a `BigRational`.
    def <=>(other : BigRational) : Int32
      if @scale == 0
        @value <=> other
      else
        @value * other.denominator <=> power_ten_to(@scale) * other.numerator
      end
    end

    # Compares `self` with a primitive `Float`. Returns `nil` if *other* is NaN.
    def <=>(other : Float::Primitive) : Int32?
      return nil if other.nan?
      if sign = other.infinite?
        return -sign
      end
      self <=> BigDecimal.new(other)
    end

    # Compares `self` with an `Int`.
    def <=>(other : Int) : Int32
      self <=> BigDecimal.new(other)
    end

    # Returns `true` if `self` and *other* represent the same value.
    def ==(other : BigDecimal) : Bool
      case @scale
      when .>(other.scale)
        scaled = other.value * power_ten_to(@scale - other.scale)
        @value == scaled
      when .<(other.scale)
        scaled = @value * power_ten_to(other.scale - @scale)
        scaled == other.value
      else
        @value == other.value
      end
    end

    # --- Predicates ---

    # Returns `true` if the value is zero.
    def zero? : Bool
      @value.zero?
    end

    # Returns `true` if the value is positive.
    def positive? : Bool
      @value.positive?
    end

    # Returns `true` if the value is negative.
    def negative? : Bool
      @value.negative?
    end

    # Returns the sign as -1, 0, or 1.
    def sign : Int32
      @value.sign
    end

    # Returns `true` if this decimal represents an integer (scale is effectively zero).
    def integer? : Bool
      factor_powers_of_ten
      @scale == 0
    end

    # --- Scaling ---

    # Returns a new `BigDecimal` scaled to match *new_scale*'s scale.
    def scale_to(new_scale : BigDecimal) : BigDecimal
      in_scale(new_scale.scale)
    end

    private def in_scale(new_scale : UInt64) : BigDecimal
      if @value.zero?
        BigDecimal.new(BigInt.new(0), new_scale)
      elsif @scale > new_scale
        scale_diff = @scale - new_scale
        BigDecimal.new(@value // power_ten_to(scale_diff), new_scale)
      elsif @scale < new_scale
        scale_diff = new_scale - @scale
        BigDecimal.new(@value * power_ten_to(scale_diff), new_scale)
      else
        self
      end
    end

    # --- Rounding ---

    # Rounds towards positive infinity.
    def ceil : BigDecimal
      round_impl { |rem| rem > BigInt.new(0) }
    end

    # Rounds towards negative infinity.
    def floor : BigDecimal
      round_impl { |rem| rem < BigInt.new(0) }
    end

    # Rounds towards zero (truncation).
    def trunc : BigDecimal
      round_impl { false }
    end

    # Rounds to the nearest integer, ties to even (banker's rounding).
    def round_even : BigDecimal
      round_impl do |rem, rem_range, mantissa|
        case rem.abs <=> rem_range // BigInt.new(2)
        when .<(0)
          false
        when .>(0)
          true
        else
          mantissa.odd?
        end
      end
    end

    # Rounds to the nearest integer, ties away from zero.
    def round_away : BigDecimal
      round_impl { |rem, rem_range| rem.abs >= rem_range // BigInt.new(2) }
    end

    private def round_impl(&)
      return self if @scale <= 0 || zero?

      multiplier = power_ten_to(@scale)
      mantissa, rem = @value.unsafe_truncated_divmod(multiplier)

      round_away = yield rem, multiplier, mantissa
      mantissa = mantissa + BigInt.new(sign) if round_away

      BigDecimal.new(mantissa, 0_u64)
    end

    # --- Conversions ---

    # Returns the string representation of this decimal.
    #
    # ```
    # BigNumber::BigDecimal.new("1.20").to_s # => "1.2"
    # ```
    def to_s : String
      String.build { |io| to_s(io) }
    end

    # Writes the string representation to *io*.
    def to_s(io : IO) : Nil
      factor_powers_of_ten

      str = @value.abs.to_s
      is_negative = @value.negative?

      io << '-' if is_negative

      if @scale == 0
        io << str
        io << ".0"
      elsif @scale >= str.size.to_u64
        # Value is less than 1: 0.00...digits
        io << "0."
        (@scale - str.size).times { io << '0' }
        # Strip trailing zeros
        stripped = str.rstrip('0')
        stripped = "0" if stripped.empty?
        io << stripped
      else
        # Insert decimal point
        point_pos = str.size - @scale.to_i32
        io << str[0...point_pos]
        io << '.'
        frac = str[point_pos..]
        stripped = frac.rstrip('0')
        stripped = "0" if stripped.empty?
        io << stripped
      end
    end

    # :nodoc:
    def inspect(io : IO) : Nil
      to_s(io)
    end

    # :nodoc:
    def inspect : String
      to_s
    end

    # Converts to `BigInt` by truncating the fractional part.
    def to_big_i : BigInt
      trunc.value
    end

    # Converts to `BigFloat` with the given *precision* in bits.
    def to_big_f(*, precision : Int32 = BigFloat.default_precision) : BigFloat
      BigFloat.new(to_s, precision: precision)
    end

    # Returns `self`.
    def to_big_d : BigDecimal
      self
    end

    # Converts to an exact `BigRational` representation.
    def to_big_r : BigRational
      BigRational.new(@value, power_ten_to(@scale))
    end

    # Converts to `Int32` (truncates, raises on overflow).
    def to_i : Int32
      to_i32
    end

    # Converts to `Int32` (truncates, wraps on overflow).
    def to_i! : Int32
      to_i32!
    end

    # Converts to `UInt32` (truncates, raises on overflow).
    def to_u : UInt32
      to_u32
    end

    # Converts to `UInt32` (truncates, wraps on overflow).
    def to_u! : UInt32
      to_u32!
    end

    {% for info in [{Int8, "i8"}, {Int16, "i16"}, {Int32, "i32"}, {Int64, "i64"}] %}
      # Converts to `{{info[0]}}` (truncates, raises on overflow).
      def to_{{info[1].id}} : {{info[0]}}
        to_big_i.to_{{info[1].id}}
      end

      # Converts to `{{info[0]}}` (truncates, wraps on overflow).
      def to_{{info[1].id}}! : {{info[0]}}
        to_big_i.to_{{info[1].id}}!
      end
    {% end %}

    private def to_big_u : BigInt
      raise OverflowError.new if negative?
      to_big_u!
    end

    private def to_big_u! : BigInt
      @value.abs // power_ten_to(@scale)
    end

    {% for info in [{UInt8, "u8"}, {UInt16, "u16"}, {UInt32, "u32"}, {UInt64, "u64"}] %}
      # Converts to `{{info[0]}}` (truncates, raises on overflow).
      def to_{{info[1].id}} : {{info[0]}}
        to_big_u.to_{{info[1].id}}
      end

      # Converts to `{{info[0]}}` (truncates, wraps on overflow).
      def to_{{info[1].id}}! : {{info[0]}}
        to_big_u!.to_{{info[1].id}}!
      end
    {% end %}

    # Converts to `Float64`.
    def to_f64 : Float64
      to_s.to_f64
    end

    # Converts to `Float32`.
    def to_f32 : Float32
      to_f64.to_f32
    end

    # Converts to `Float64`.
    def to_f : Float64
      to_f64
    end

    # Converts to `Float32` (wraps on overflow).
    def to_f32! : Float32
      to_f64.to_f32!
    end

    # Converts to `Float64` (never overflows).
    def to_f64! : Float64
      to_f64
    end

    # Converts to `Float64` (never overflows).
    def to_f! : Float64
      to_f64!
    end

    # Returns `self` (value type, no copy needed).
    def clone : BigDecimal
      self
    end

    # :nodoc:
    def hash(hasher)
      hasher = @value.hash(hasher)
      hasher = @scale.hash(hasher)
      hasher
    end

    # --- Internal helpers ---

    # :nodoc:
    def normalize_quotient(other : BigDecimal, quotient : BigInt) : BigInt
      if (@value.negative? && other.value.positive?) || (other.value.negative? && @value.positive?)
        -quotient.abs
      else
        quotient
      end
    end

    private def check_division_by_zero(bd : BigDecimal)
      raise DivisionByZeroError.new if bd.value.zero?
    end

    private def power_ten_to(x : Int) : BigInt
      TEN_I ** x
    end

    # :nodoc:
    protected def mul_power_of_ten(exponent : Int) : BigDecimal
      if exponent <= @scale
        BigDecimal.new(@value, @scale - exponent)
      else
        BigDecimal.new(@value * power_ten_to(exponent - @scale), 0_u64)
      end
    end

    # :nodoc:
    protected def factor_powers_of_ten : Nil
      if @scale > 0
        neg = @value.negative?
        reduced, exp = @value.factor_by(TEN)
        reduced = -reduced if neg
        if exp <= @scale
          @value = reduced
          @scale -= exp
        else
          @value = @value // power_ten_to(@scale)
          @scale = 0_u64
        end
      end
    end
  end
end
