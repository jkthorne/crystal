module BigNumber
  # Converts a finite float's truncated integer part to a `BigInt`.
  # Uses binary decomposition of IEEE 754 representation to avoid precision loss
  # from string conversion.
  protected def self.float_to_bigint(f : Float64) : BigInt
    return BigInt.new(0) if f == 0.0
    neg = f < 0
    f = -f if neg
    # Decompose f = mantissa * 2^exponent
    # IEEE 754: 52-bit mantissa, 11-bit exponent
    bits = f.unsafe_as(UInt64)
    raw_exp = ((bits >> 52) & 0x7FF).to_i32
    mantissa = bits & ((1_u64 << 52) - 1)
    if raw_exp == 0
      # Denormalized
      exp = -1074
    else
      mantissa |= (1_u64 << 52) # implicit leading 1
      exp = raw_exp - 1023 - 52
    end
    result = BigInt.new(mantissa)
    if exp > 0
      result = result << exp
    elsif exp < 0
      result = result >> (-exp)
    end
    neg ? -result : result
  end

  # Arbitrary-precision integer using sign-magnitude representation.
  #
  # Internally stores the magnitude as an array of `UInt64` limbs in
  # least-significant-first order. The sign is encoded in `@size`:
  # positive `@size` means a positive number, negative means negative,
  # and zero means the value is zero.
  #
  # Supports the full range of integer arithmetic, bitwise operations,
  # number theory (GCD, primality testing, modular exponentiation), and
  # conversions. Multiplication uses schoolbook, Karatsuba, or NTT
  # depending on operand size; division uses Knuth Algorithm D or
  # Burnikel-Ziegler.
  #
  # ```
  # a = BigNumber::BigInt.new("123456789012345678901234567890")
  # b = BigNumber::BigInt.new(42)
  # puts a * b # => 5185185138503358533451851851180
  # ```
  struct BigInt
    include Comparable(BigInt)
    include Comparable(Int)

    @limbs : Pointer(Limb)
    @alloc : Int32
    @size : Int32 # positive = positive number, negative = negative number, 0 = zero

    # --- Construction ---

    # Creates a `BigInt` with value zero.
    def initialize
      @limbs = Pointer(Limb).null
      @alloc = 0
      @size = 0
    end

    # Creates a `BigInt` from a signed integer primitive.
    #
    # ```
    # BigNumber::BigInt.new(-42) # => -42
    # ```
    def initialize(value : Int8 | Int16 | Int32 | Int64 | Int128)
      @limbs = Pointer(Limb).null
      @alloc = 0
      @size = 0
      if value == 0
        return
      end
      neg = value < 0
      # Get absolute value as UInt128 to handle Int64::MIN safely
      mag = neg ? (0_u128 &- value.to_u128!) : value.to_u128
      set_from_unsigned(mag)
      @size = -@size if neg
    end

    # Creates a `BigInt` by copying another `BigInt`.
    def initialize(other : BigInt)
      n = other.abs_size
      if n == 0
        @limbs = Pointer(Limb).null
        @alloc = 0
        @size = 0
      else
        @limbs = Pointer(Limb).malloc(n)
        @alloc = n
        @limbs.copy_from(other.@limbs, n)
        @size = other.@size
      end
    end

    # Creates a `BigInt` from an unsigned integer primitive.
    def initialize(value : UInt8 | UInt16 | UInt32 | UInt64 | UInt128)
      @limbs = Pointer(Limb).null
      @alloc = 0
      @size = 0
      return if value == 0
      set_from_unsigned(value.to_u128)
    end

    # Creates a `BigInt` by parsing a string in the given *base* (2 to 36).
    # Supports optional leading `+` or `-` sign. Digits are parsed in chunks
    # for efficiency using the largest chunk that fits in a `UInt64`.
    #
    # ```
    # BigNumber::BigInt.new("ff", 16) # => 255
    # BigNumber::BigInt.new("-101", 2) # => -5
    # ```
    def initialize(str : String, base : Int32 = 10)
      @limbs = Pointer(Limb).null
      @alloc = 0
      @size = 0
      raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36
      raise ArgumentError.new("Empty string") if str.empty?

      i = 0
      neg = false
      if str[i] == '-'
        neg = true
        i += 1
      elsif str[i] == '+'
        i += 1
      end
      raise ArgumentError.new("No digits in #{str.inspect}") if i >= str.size

      # Skip leading zeros
      while i < str.size && str[i] == '0'
        i += 1
      end
      if i >= str.size
        # All zeros
        return
      end

      # Process digits: accumulate in chunks for efficiency.
      # We pick a chunk size so that base^chunk fits in a UInt64.
      chunk_size, chunk_base = BigInt.chunk_params(base)

      while i < str.size
        # Grab up to chunk_size digits
        chunk_end = Math.min(i + chunk_size, str.size)
        actual_chunk = chunk_end - i
        digit_val = 0_u64
        multiplier = 1_u64
        # Compute base^actual_chunk and the digit value
        actual_base = 1_u64
        j = i
        while j < chunk_end
          d = BigInt.char_to_digit(str[j], base)
          digit_val = digit_val &* base.to_u64 &+ d.to_u64
          actual_base = actual_base &* base.to_u64
          j += 1
        end
        # self = self * actual_base + digit_val
        n = abs_size
        if n == 0
          # First chunk: just set the value
          if digit_val != 0
            ensure_capacity(1)
            @limbs[0] = digit_val
            @size = 1
          end
        else
          ensure_capacity(n + 1)
          carry = BigInt.limbs_mul_1(@limbs, @limbs, n, actual_base)
          if digit_val != 0
            add_carry = BigInt.limbs_add_1(@limbs, @limbs, n, digit_val)
            carry = carry &+ add_carry
          end
          if carry != 0
            @limbs[n] = carry
            @size = n + 1
          end
        end
        i = chunk_end
      end

      @size = -@size if neg && @size != 0
    end

    # Creates a `BigInt` from an enumerable of digit values, least-significant first.
    # Each digit must be in `0...base`.
    #
    # ```
    # BigNumber::BigInt.from_digits([5, 4, 3, 2, 1], 10) # => 12345
    # ```
    def self.from_digits(digits : Enumerable(Int), base : Int = 10) : self
      raise ArgumentError.new("Invalid base #{base}") if base < 2
      result = BigInt.new(0)
      multiplier = BigInt.new(1)
      b = BigInt.new(base)
      digits.each do |digit|
        raise ArgumentError.new("Invalid digit #{digit}") if digit < 0
        raise ArgumentError.new("Invalid digit #{digit} for base #{base}") if digit >= base
        result = result + multiplier * BigInt.new(digit)
        multiplier = multiplier * b
      end
      result
    end

    # --- Accessors ---

    # Returns the number of limbs (absolute value of `@size`).
    @[AlwaysInline]
    def abs_size : Int32
      @size < 0 ? -@size : @size
    end

    # Returns `true` if this integer is zero.
    @[AlwaysInline]
    def zero? : Bool
      @size == 0
    end

    # Returns `true` if this integer is negative.
    @[AlwaysInline]
    def negative? : Bool
      @size < 0
    end

    # Returns `true` if this integer is strictly positive.
    @[AlwaysInline]
    def positive? : Bool
      @size > 0
    end

    # Returns `true` if this integer is even (or zero).
    @[AlwaysInline]
    def even? : Bool
      zero? || (@limbs[0] & 1_u64) == 0
    end

    # Returns `true` if this integer is odd.
    @[AlwaysInline]
    def odd? : Bool
      !zero? && (@limbs[0] & 1_u64) == 1
    end

    # Returns -1, 0, or 1 depending on the sign of this integer.
    @[AlwaysInline]
    def sign : Int32
      @size < 0 ? -1 : (@size > 0 ? 1 : 0)
    end

    # --- Comparison ---

    # Compares this `BigInt` with another. Returns -1, 0, or 1.
    def <=>(other : BigInt) : Int32
      # Different signs: negative < zero < positive
      if @size != other.@size
        sa = @size < 0 ? -1 : (@size > 0 ? 1 : 0)
        sb = other.@size < 0 ? -1 : (other.@size > 0 ? 1 : 0)
        return sa - sb if sa != sb
      end
      # Same sign. Compare magnitudes.
      an = abs_size
      bn = other.abs_size
      cmp = BigInt.limbs_cmp(@limbs, an, other.@limbs, bn)
      @size < 0 ? -cmp : cmp
    end

    # Compares with a primitive integer. Fast path avoids `BigInt` allocation.
    def <=>(other : Int) : Int32
      # Fast path: avoid allocation for single/zero-limb comparisons
      other_neg = other < 0
      if negative? && !other_neg
        return -1
      elsif !negative? && other_neg
        return zero? && other == 0 ? 0 : (negative? ? -1 : 1)
      end
      # Same sign
      if other == 0
        return zero? ? 0 : (negative? ? -1 : 1)
      end
      mag = other_neg ? (0_u128 &- other.to_u128!) : other.to_u128
      lo = mag.to_u64!
      hi = (mag >> 64).to_u64!
      other_size = hi != 0 ? 2 : 1
      n = abs_size
      if n != other_size
        cmp = n > other_size ? 1 : -1
        return negative? ? -cmp : cmp
      end
      # Same number of limbs — compare from top
      if other_size == 2
        cmp = if @limbs[1] != hi
                @limbs[1] > hi ? 1 : -1
              elsif @limbs[0] != lo
                @limbs[0] > lo ? 1 : -1
              else
                0
              end
      else
        cmp = if @limbs[0] != lo
                @limbs[0] > lo ? 1 : -1
              else
                0
              end
      end
      negative? ? -cmp : cmp
    end

    # Compares with a float. Returns `nil` for NaN. Uses binary decomposition
    # of the float to avoid precision loss.
    def <=>(other : Float::Primitive) : Int32?
      return nil if other.nan?
      if other.infinite?
        return other > 0 ? -1 : 1
      end
      f = other.to_f64
      # Check if float has a fractional part
      trunc = LibM.trunc_f64(f)
      has_frac = f != trunc
      # Build BigInt from the integer part of the float via binary decomposition
      other_int = BigNumber.float_to_bigint(f)
      cmp = self <=> other_int
      if cmp != 0
        cmp < 0 ? -1 : 1
      elsif has_frac
        # self == integer part of other, but other has fractional part
        f > 0 ? -1 : 1
      else
        0
      end
    end

    # Returns `true` if both `BigInt` values are equal (same sign and magnitude).
    def ==(other : BigInt) : Bool
      return false if @size != other.@size
      n = abs_size
      n.times do |i|
        return false if @limbs[i] != other.@limbs[i]
      end
      true
    end

    # Returns `true` if equal to a primitive integer. Fast path avoids allocation.
    def ==(other : Int) : Bool
      # Fast path: avoid allocation for small comparisons
      if other == 0
        return zero?
      end
      neg = other < 0
      return false if neg != negative?
      mag = neg ? (0_u128 &- other.to_u128!) : other.to_u128
      lo = mag.to_u64!
      hi = (mag >> 64).to_u64!
      if hi != 0
        return false if abs_size != 2
        @limbs[0] == lo && @limbs[1] == hi
      else
        return false if abs_size != 1
        @limbs[0] == lo
      end
    end

    # Feeds sign and limbs into the hasher for use in `Hash` and `Set`.
    def hash(hasher)
      hasher = @size.hash(hasher)
      abs_size.times do |i|
        hasher = @limbs[i].hash(hasher)
      end
      hasher
    end

    # --- Unary ---

    # Returns the negation of this integer.
    def - : BigInt
      result = dup_value
      result.negate!
      result
    end

    # Returns the absolute value.
    def abs : BigInt
      result = dup_value
      result.abs!
      result
    end

    # --- Addition & Subtraction ---

    # Returns the sum of two `BigInt` values. Uses a single-limb fast path
    # when both operands fit in one limb.
    def +(other : BigInt) : BigInt
      return dup_value if other.zero?
      return other.dup_value if zero?

      # Single-limb fast path
      if @size.abs == 1 && other.@size.abs == 1
        a = @limbs[0].to_i128
        a = -a if @size < 0
        b = other.@limbs[0].to_i128
        b = -b if other.@size < 0
        return BigInt.new(a + b)
      end

      if (@size ^ other.@size) >= 0
        # Same sign: add magnitudes, keep sign
        add_magnitudes(other)
      else
        # Different signs: subtract magnitudes
        sub_magnitudes(other)
      end
    end

    # :ditto:
    def +(other : Int) : BigInt
      self + BigInt.new(other)
    end

    # Returns the difference of two `BigInt` values.
    def -(other : BigInt) : BigInt
      return dup_value if other.zero?
      if zero?
        result = other.dup_value
        result.negate!
        return result
      end

      # Single-limb fast path
      if @size.abs == 1 && other.@size.abs == 1
        a = @limbs[0].to_i128
        a = -a if @size < 0
        b = other.@limbs[0].to_i128
        b = -b if other.@size < 0
        return BigInt.new(a - b)
      end

      if (@size ^ other.@size) < 0
        # Different signs: add magnitudes, keep self's sign
        add_magnitudes(other)
      else
        # Same sign: subtract magnitudes
        sub_magnitudes(other)
      end
    end

    # :ditto:
    def -(other : Int) : BigInt
      self - BigInt.new(other)
    end

    # --- Multiplication ---

    # Returns the product of two `BigInt` values.
    # Dispatches to schoolbook (< 48 limbs), Karatsuba (48-24999 limbs),
    # or NTT (>= 25000 limbs) multiplication based on operand size.
    # Includes a single-limb fast path using `UInt128`.
    def *(other : BigInt) : BigInt
      return BigInt.new if zero? || other.zero?

      # Single-limb fast path: use UInt128 multiply
      if @size.abs == 1 && other.@size.abs == 1
        prod = @limbs[0].to_u128 &* other.@limbs[0].to_u128
        result = BigInt.new(capacity: 2)
        result.@limbs[0] = prod.to_u64!
        hi = (prod >> 64).to_u64!
        if hi != 0
          result.@limbs[1] = hi
          result.set_size(2)
        else
          result.set_size(1)
        end
        if (@size < 0) ^ (other.@size < 0)
          result.set_size(-result.@size)
        end
        return result
      end

      an = abs_size
      bn = other.abs_size
      rn = an + bn
      result = BigInt.new(capacity: rn)
      if an >= bn
        BigInt.limbs_mul(result.@limbs, @limbs, an, other.@limbs, bn)
      else
        BigInt.limbs_mul(result.@limbs, other.@limbs, bn, @limbs, an)
      end
      result.set_size(rn)
      result.normalize!
      # Sign: negative if exactly one operand is negative
      if (@size < 0) ^ (other.@size < 0)
        result.set_size(-result.@size)
      end
      result
    end

    # Multiplies by a primitive integer. Fast path uses `limbs_mul_1` for
    # single-limb multipliers, avoiding temporary `BigInt` allocation.
    def *(other : Int) : BigInt
      return BigInt.new if zero? || other == 0
      # Fast path: multiply by single limb without constructing a temporary BigInt
      neg = (negative?) ^ (other < 0)
      mag = other < 0 ? (0_u128 &- other.to_u128!) : other.to_u128
      lo = mag.to_u64!
      hi = (mag >> 64).to_u64!
      if hi == 0
        n = abs_size
        result = BigInt.new(capacity: n + 1)
        carry = BigInt.limbs_mul_1(result.@limbs, @limbs, n, lo)
        if carry != 0
          result.@limbs[n] = carry
          result.set_size(n + 1)
        else
          result.set_size(n)
        end
        result.set_size(-result.@size) if neg
        return result
      end
      self * BigInt.new(other)
    end

    # --- Division ---

    # Returns `{quotient, remainder}` with truncation toward zero (T-division).
    # The remainder has the same sign as the dividend.
    # Uses single-limb fast path, Knuth Algorithm D (< 80 limbs), or
    # Burnikel-Ziegler (>= 80 limbs).
    def tdiv_rem(other : BigInt) : {BigInt, BigInt}
      raise DivisionByZeroError.new if other.zero?
      an = abs_size
      bn = other.abs_size
      cmp = BigInt.limbs_cmp(@limbs, an, other.@limbs, bn)
      if cmp == 0
        # |self| == |other|
        q = BigInt.new(1)
        if (@size < 0) ^ (other.@size < 0)
          q.set_size(-1)
        end
        return {q, BigInt.new}
      elsif cmp < 0
        # |self| < |other| => quotient is 0, remainder is self
        return {BigInt.new, dup_value}
      end

      # Single-limb divisor fast path
      if bn == 1
        q = BigInt.new(capacity: an)
        rem_limb = BigInt.limbs_div_rem_1(q.@limbs, @limbs, an, other.@limbs[0])
        q.set_size(an)
        q.normalize!
        r = BigInt.new
        if rem_limb != 0
          r = BigInt.new(capacity: 1)
          r.@limbs[0] = rem_limb
          r.set_size(1)
        end
        # Signs
        if (@size < 0) ^ (other.@size < 0)
          q.set_size(-q.@size)
        end
        if @size < 0
          r.set_size(-r.@size)
        end
        return {q, r}
      end

      # Multi-limb division
      qn = an - bn + 1
      q = BigInt.new(capacity: qn)
      r = BigInt.new(capacity: bn)
      if bn >= BZ_THRESHOLD
        BigInt.limbs_div_rem_bz(q.@limbs, r.@limbs, @limbs, an, other.@limbs, bn)
      else
        scratch = Pointer(Limb).malloc(an + bn + 1)
        BigInt.limbs_div_rem(q.@limbs, r.@limbs, @limbs, an, other.@limbs, bn, scratch)
      end
      q.set_size(qn)
      q.normalize!
      r.set_size(bn)
      r.normalize!
      # Signs
      if (@size < 0) ^ (other.@size < 0)
        q.set_size(-q.@size)
      end
      if @size < 0 && r.@size != 0
        r.set_size(-r.@size)
      end
      {q, r}
    end

    # Returns `{quotient, modulus}` with floor division (F-division).
    # The quotient rounds toward negative infinity, and the modulus has the
    # same sign as the divisor. This is Crystal's convention for `//` and `%`.
    def divmod(other : BigInt) : {BigInt, BigInt}
      q, r = tdiv_rem(other)
      # If remainder is nonzero and signs of dividend and divisor differ, adjust
      if !r.zero? && ((@size < 0) ^ (other.@size < 0))
        q = q - 1
        r = r + other
      end
      {q, r}
    end

    # Returns the floor-division quotient (rounds toward negative infinity).
    def //(other : BigInt) : BigInt
      divmod(other)[0]
    end

    # :ditto:
    def //(other : Int) : BigInt
      self // BigInt.new(other)
    end

    # Returns the modulus (same sign as divisor, floor-division convention).
    def %(other : BigInt) : BigInt
      divmod(other)[1]
    end

    # :ditto:
    def %(other : Int) : BigInt
      self % BigInt.new(other)
    end

    # Returns the truncated quotient (rounds toward zero).
    def tdiv(other : BigInt) : BigInt
      tdiv_rem(other)[0]
    end

    # Returns the truncated remainder (same sign as dividend).
    def tmod(other : BigInt) : BigInt
      tdiv_rem(other)[1]
    end

    # Alias for `tmod` -- returns the truncated remainder.
    def remainder(other : BigInt) : BigInt
      tmod(other)
    end

    # :ditto:
    def remainder(other : Int) : BigInt
      tmod(BigInt.new(other))
    end

    # Wrapping addition -- identical to `+` since `BigInt` cannot overflow.
    def &+(other) : BigInt
      self + other
    end

    # Wrapping subtraction -- identical to `-` since `BigInt` cannot overflow.
    def &-(other) : BigInt
      self - other
    end

    # Wrapping multiplication -- identical to `*` since `BigInt` cannot overflow.
    def &*(other) : BigInt
      self * other
    end

    # Unsafe floored division -- identical to `//` for `BigInt` (no overflow possible).
    def unsafe_floored_div(other : BigInt) : BigInt
      self // other
    end

    # :ditto:
    def unsafe_floored_div(other : Int) : BigInt
      self // other
    end

    # Unsafe floored mod -- identical to `%` for `BigInt`.
    def unsafe_floored_mod(other : BigInt) : BigInt
      self % other
    end

    # :ditto:
    def unsafe_floored_mod(other : Int) : BigInt
      self % other
    end

    # Unsafe floored divmod -- identical to `divmod` for `BigInt`.
    def unsafe_floored_divmod(other : BigInt) : {BigInt, BigInt}
      divmod(other)
    end

    # :ditto:
    def unsafe_floored_divmod(other : Int) : {BigInt, BigInt}
      divmod(BigInt.new(other))
    end

    # Unsafe truncated division -- identical to `tdiv` for `BigInt`.
    def unsafe_truncated_div(other : BigInt) : BigInt
      tdiv(other)
    end

    # :ditto:
    def unsafe_truncated_div(other : Int) : BigInt
      tdiv(BigInt.new(other))
    end

    # Unsafe truncated mod -- identical to `tmod` for `BigInt`.
    def unsafe_truncated_mod(other : BigInt) : BigInt
      tmod(other)
    end

    # :ditto:
    def unsafe_truncated_mod(other : Int) : BigInt
      tmod(BigInt.new(other))
    end

    # Unsafe truncated divmod -- identical to `tdiv_rem` for `BigInt`.
    def unsafe_truncated_divmod(other : BigInt) : {BigInt, BigInt}
      tdiv_rem(other)
    end

    # :ditto:
    def unsafe_truncated_divmod(other : Int) : {BigInt, BigInt}
      tdiv_rem(BigInt.new(other))
    end

    # --- Exponentiation ---

    # Raises this integer to the power *exp* using binary exponentiation
    # (square-and-multiply). Raises `ArgumentError` for negative exponents.
    #
    # ```
    # BigNumber::BigInt.new(2) ** 100 # => 1267650600228229401496703205376
    # ```
    def **(exp : Int) : BigInt
      raise ArgumentError.new("Negative exponent #{exp}") if exp < 0
      return BigInt.new(1) if exp == 0
      return dup_value if exp == 1
      return BigInt.new if zero?

      base = dup_value
      result = BigInt.new(1)
      e = exp.to_i64
      while e > 0
        if e.odd?
          result = result * base
        end
        e >>= 1
        base = base * base if e > 0
      end
      result
    end

    # Computes `self ** exp % mod` efficiently.
    # Uses Montgomery multiplication (REDC) for multi-limb odd moduli,
    # falling back to standard square-and-multiply for even or single-limb moduli.
    #
    # ```
    # base = BigNumber::BigInt.new(3)
    # base.pow_mod(1000, BigNumber::BigInt.new(997)) # => 1
    # ```
    def pow_mod(exp : BigInt, mod : BigInt) : BigInt
      raise ArgumentError.new("Negative exponent") if exp.negative?
      raise ArgumentError.new("Modulus must be positive") if !mod.positive?
      return BigInt.new if mod.abs_size == 1 && mod.@limbs[0] == 1_u64
      if exp.zero?
        return BigInt.new(1) % mod
      end

      # Use Montgomery multiplication for multi-limb odd moduli
      mn = mod.abs_size
      if mn >= 2 && (mod.@limbs[0] & 1_u64) == 1_u64
        return montgomery_pow_mod(exp, mod)
      end

      # Fallback: standard square-and-multiply
      base = self % mod
      result = BigInt.new(1)
      bits = exp.bit_length
      i = 0
      while i < bits
        if exp.bit(i) == 1
          result = (result * base) % mod
        end
        i += 1
        base = (base * base) % mod if i < bits
      end
      result
    end

    # Montgomery modular exponentiation for odd moduli >= 2 limbs.
    # Converts operands into Montgomery form (aR mod m), performs square-and-multiply
    # with REDC, then converts back. Replaces expensive division with multiply-and-shift.
    private def montgomery_pow_mod(exp : BigInt, mod : BigInt) : BigInt
      mn = mod.abs_size
      m = mod.@limbs

      # Compute m' = -m[0]^(-1) mod 2^64
      # Uses Newton's method: x_{n+1} = x_n * (2 - m[0] * x_n)
      m_inv = 1_u64
      8.times do
        m_inv = m_inv &* (2_u64 &- m[0] &* m_inv)
      end
      m_inv = 0_u64 &- m_inv # negate to get -m^(-1) mod 2^64

      # R = 2^(64*mn). Compute R mod m and R^2 mod m.
      # R mod m = (1 << (64*mn)) % mod
      r_mod_m = (BigInt.new(1) << (64 * mn)) % mod
      # R^2 mod m for converting to Montgomery form
      r2_mod_m = (r_mod_m * r_mod_m) % mod

      # Convert base to Montgomery form: aR mod m = montgomery_reduce(a * R^2, m, m')
      base_reduced = (self % mod)
      base_reduced = base_reduced + mod if base_reduced.negative?

      base_mont = mont_mul(base_reduced, r2_mod_m, mod, m_inv, mn)
      result_mont = r_mod_m

      bits = exp.bit_length
      i = bits - 1
      while i >= 0
        result_mont = mont_mul(result_mont, result_mont, mod, m_inv, mn)
        if exp.bit(i) == 1
          result_mont = mont_mul(result_mont, base_mont, mod, m_inv, mn)
        end
        i -= 1
      end

      # Convert back from Montgomery form: result = REDC(result_mont)
      mont_reduce(result_mont, mod, m_inv, mn)
    end

    # Montgomery multiplication: computes `(a * b * R^-1) mod m` where R = 2^(64*mn).
    private def mont_mul(a : BigInt, b : BigInt, mod : BigInt, m_inv : UInt64, mn : Int32) : BigInt
      # Product t = a * b (up to 2*mn limbs)
      t = a * b
      mont_reduce(t, mod, m_inv, mn)
    end

    # Montgomery reduction (REDC): computes `t * R^-1 mod m` using mn iterations
    # of `limbs_addmul_1` with carry propagation and a final conditional subtraction.
    private def mont_reduce(t : BigInt, mod : BigInt, m_inv : UInt64, mn : Int32) : BigInt
      # Work on a mutable copy with enough space
      tn = mn * 2 + 2
      tp = Pointer(Limb).malloc(tn)
      ta = t.abs_size
      tp.copy_from(t.@limbs, ta)

      m = mod.@limbs
      i = 0
      while i < mn
        # u = t[i] * m' mod 2^64
        u = tp[i] &* m_inv
        # t += u * m * 2^(64*i)
        carry = BigInt.limbs_addmul_1(tp + i, m, mn, u)
        # Propagate carry
        j = i + mn
        while carry > 0 && j < tn
          sum = tp[j].to_u128 &+ carry.to_u128
          tp[j] = sum.to_u64!
          carry = (sum >> 64).to_u64!
          j += 1
        end
        i += 1
      end

      # Result = t >> (64*mn), i.e., tp[mn..2*mn-1]
      rn = tn - mn
      while rn > 0 && tp[mn + rn - 1] == 0
        rn -= 1
      end
      if rn == 0
        return BigInt.new
      end
      result = BigInt.new(capacity: rn)
      result.@limbs.copy_from(tp + mn, rn)
      result.set_size(rn)

      # Final subtraction if result >= mod
      if BigInt.limbs_cmp(result.@limbs, result.abs_size, mod.@limbs, mn) >= 0
        result = result - mod
      end
      result
    end

    # :ditto:
    def pow_mod(exp : Int, mod : BigInt) : BigInt
      pow_mod(BigInt.new(exp), mod)
    end

    # :ditto:
    def pow_mod(exp : Int, mod : BigInt) : BigInt
      pow_mod(BigInt.new(exp), mod)
    end

    # :ditto:
    def pow_mod(exp : BigInt | Int, mod : Int) : BigInt
      pow_mod(BigInt.new(exp), BigInt.new(mod))
    end

    # --- Bitwise Operations ---

    # Returns the bitwise NOT (two's complement): `~x = -(x + 1)`.
    def ~ : BigInt
      # ~x = -(x + 1)
      if negative?
        # ~(-x) = x - 1
        self.abs - 1
      else
        # ~x = -(x + 1)
        -(self + 1)
      end
    end

    # Left-shifts by *count* bits. Negative counts shift right.
    def <<(count : Int) : BigInt
      return self >> (-count) if count < 0
      return dup_value if count == 0
      return BigInt.new if zero?

      whole_limbs = count.to_i32 // 64
      bit_shift = count.to_i32 % 64

      n = abs_size
      new_size = n + whole_limbs + (bit_shift > 0 ? 1 : 0)
      result = BigInt.new(capacity: new_size)

      # Zero the bottom limbs
      whole_limbs.times { |i| result.@limbs[i] = 0_u64 }

      if bit_shift > 0
        carry = BigInt.limbs_lshift(result.@limbs + whole_limbs, @limbs, n, bit_shift)
        result.@limbs[whole_limbs + n] = carry
      else
        (result.@limbs + whole_limbs).copy_from(@limbs, n)
      end

      result.set_size(new_size)
      result.normalize!
      result.set_size(-result.@size) if negative?
      result
    end

    # Arithmetic right-shifts by *count* bits. For negative numbers, rounds
    # toward negative infinity (floor division by 2^count).
    def >>(count : Int) : BigInt
      return self << (-count) if count < 0
      return dup_value if count == 0
      return BigInt.new if zero?

      whole_limbs = count.to_i32 // 64
      bit_shift = count.to_i32 % 64

      n = abs_size
      # If shifting away all limbs
      if whole_limbs >= n
        return negative? ? BigInt.new(-1) : BigInt.new
      end

      new_size = n - whole_limbs
      result = BigInt.new(capacity: new_size)

      if bit_shift > 0
        BigInt.limbs_rshift(result.@limbs, @limbs + whole_limbs, new_size, bit_shift)
      else
        result.@limbs.copy_from(@limbs + whole_limbs, new_size)
      end

      result.set_size(new_size)
      result.normalize!

      if negative?
        # Arithmetic right shift: if any shifted-out bits were set, subtract 1 from result
        # (equivalent to floor division by 2^count for negative numbers)
        lost_bits = false
        whole_limbs.times do |i|
          if @limbs[i] != 0
            lost_bits = true
            break
          end
        end
        if !lost_bits && bit_shift > 0
          mask = (1_u64 << bit_shift) &- 1
          lost_bits = (@limbs[whole_limbs] & mask) != 0
        end
        result.set_size(-result.@size) if result.@size != 0
        if lost_bits
          result = result - 1
        end
      end

      result
    end

    # Unsafe right-shift -- identical to `>>` for `BigInt`.
    def unsafe_shr(count : Int) : self
      self >> count
    end

    # Returns the bit at position *index* (0 = LSB) as 0 or 1.
    # For negative numbers, uses two's complement semantics with infinite sign extension.
    def bit(index : Int) : Int32
      return 0 if index < 0
      limb_idx = index.to_i32 // 64
      bit_idx = index.to_i32 % 64

      if positive? || zero?
        return 0 if limb_idx >= abs_size
        (@limbs[limb_idx] >> bit_idx) & 1 == 1 ? 1 : 0
      else
        # Negative: two's complement is ~(|self| - 1)
        # bit of -x = 1 - bit_of(|x| - 1, index)
        # Compute (|self| - 1) bit without allocating a full BigInt
        # Walk limbs to find (magnitude - 1) at this position
        n = abs_size
        return 1 if limb_idx >= n # infinite sign extension

        # Compute the borrow chain for magnitude - 1
        borrow = 1_u64
        limb_val = 0_u64
        i = 0
        while i <= limb_idx
          diff = @limbs[i].to_u128 &- borrow.to_u128
          limb_val = diff.to_u64!
          borrow = (diff >> 127) != 0 ? 1_u64 : 0_u64
          i += 1
        end
        # bit of (|self| - 1) at this position
        orig_bit = (limb_val >> bit_idx) & 1
        # Complement it
        orig_bit == 1 ? 0 : 1
      end
    end

    # Returns the number of bits needed to represent the absolute value.
    # Returns 1 for zero.
    def bit_length : Int32
      return 1 if zero?
      n = abs_size
      top = @limbs[n - 1]
      (n - 1) * 64 + (64 - top.leading_zeros_count.to_i32)
    end

    # Returns the number of set bits in the binary representation.
    # Returns `UInt64::MAX` for negative numbers (infinite 1-bits in two's complement).
    def popcount : Int
      return 0 if zero?
      # For negative numbers, two's complement has infinite 1-bits
      return UInt64::MAX if negative?
      count = 0
      abs_size.times { |i| count += @limbs[i].popcount }
      count
    end

    # Returns the number of trailing zero bits. Returns 0 for zero.
    def trailing_zeros_count : Int
      return 0 if zero?
      n = abs_size
      i = 0
      while i < n
        if @limbs[i] != 0
          return i * 64 + @limbs[i].trailing_zeros_count.to_i32
        end
        i += 1
      end
      0
    end

    # Bitwise AND with two's complement semantics.
    def &(other : BigInt) : BigInt
      bitwise_op(other, :and)
    end

    # :ditto:
    def &(other : Int) : BigInt
      self & BigInt.new(other)
    end

    # Bitwise OR with two's complement semantics.
    def |(other : BigInt) : BigInt
      bitwise_op(other, :or)
    end

    # :ditto:
    def |(other : Int) : BigInt
      self | BigInt.new(other)
    end

    # Bitwise XOR with two's complement semantics.
    def ^(other : BigInt) : BigInt
      bitwise_op(other, :xor)
    end

    # :ditto:
    def ^(other : Int) : BigInt
      self ^ BigInt.new(other)
    end

    # --- Number Theory ---

    # Returns the greatest common divisor using binary GCD (Stein's algorithm).
    # Uses only shifts and subtractions, avoiding expensive division.
    #
    # ```
    # a = BigNumber::BigInt.new(48)
    # b = BigNumber::BigInt.new(18)
    # a.gcd(b) # => 6
    # ```
    def gcd(other : BigInt) : BigInt
      a = self.abs
      b = other.abs
      return b if a.zero?
      return a if b.zero?

      # Binary GCD (Stein's algorithm): uses only shifts and subtractions
      a_shift = a.trailing_zeros_count.to_i32
      b_shift = b.trailing_zeros_count.to_i32
      k = Math.min(a_shift, b_shift)  # common factor of 2
      a = a >> a_shift
      b = b >> b_shift

      loop do
        # Both a and b are odd here
        cmp = a <=> b
        break if cmp == 0
        if cmp > 0
          a, b = b, a
        end
        # a <= b, both odd, so b - a is even and positive
        b = b - a
        break if b.zero?
        b = b >> b.trailing_zeros_count.to_i32
      end

      a << k
    end

    # :ditto:
    def gcd(other : Int) : Int
      gcd(BigInt.new(other)).to_i64
    end

    # Returns the least common multiple: `|self * other| / gcd(self, other)`.
    def lcm(other : BigInt) : BigInt
      return BigInt.new if zero? || other.zero?
      g = gcd(other)
      (self // g * other).abs
    end

    # :ditto:
    def lcm(other : Int) : BigInt
      lcm(BigInt.new(other))
    end

    # Returns `self!` (factorial). Raises `ArgumentError` for negative values.
    def factorial : BigInt
      raise ArgumentError.new("Factorial of negative number") if negative?
      n = to_i64
      result = BigInt.new(1)
      i = 2_i64
      while i <= n
        result = result * i
        i += 1
      end
      result
    end

    # Returns `true` if `self % number == 0`.
    def divisible_by?(number : BigInt) : Bool
      (self % number).zero?
    end

    # :ditto:
    def divisible_by?(number : Int) : Bool
      (self % number).zero?
    end

    # Returns the integer *n*-th root (floor). Uses Newton's method.
    # Delegates to `sqrt` for `n == 2`. Raises for even roots of negative numbers.
    def root(n : Int) : BigInt
      raise ArgumentError.new("Zeroth root is undefined") if n == 0
      if negative?
        raise ArgumentError.new("Even root of negative number") if n.even?
        return -((-self).root(n))
      end
      return BigInt.new if zero?
      return dup_value if n == 1
      return sqrt if n == 2

      # Newton's method for integer nth root
      # x_{k+1} = ((n-1)*x_k + self // x_k^(n-1)) // n
      bn = BigInt.new(n)
      bn1 = BigInt.new(n - 1)
      x = BigInt.new(1) << ((bit_length + n - 1) // n)
      loop do
        xn1 = x ** (n - 1)
        x1 = (bn1 * x + self // xn1) // bn
        break if x1 >= x
        x = x1
      end
      x
    end

    # Returns the integer square root (floor) using Newton's method.
    # Raises `ArgumentError` for negative values.
    def sqrt : BigInt
      raise ArgumentError.new("Square root of negative number") if negative?
      return BigInt.new if zero?
      return BigInt.new(1) if abs_size == 1 && @limbs[0] == 1_u64

      # Newton's method
      x = BigInt.new(1) << ((bit_length + 1) // 2)
      loop do
        x1 = (x + self // x) >> 1
        break if x1 >= x
        x = x1
      end
      x
    end

    # Tests primality using deterministic Miller-Rabin with 12 witnesses.
    # Deterministically correct for all numbers up to 3.3 * 10^24.
    #
    # ```
    # BigNumber::BigInt.new(104729).prime? # => true
    # ```
    def prime? : Bool
      # Quick checks without allocations
      if abs_size <= 1
        v = zero? ? 0_u64 : @limbs[0]
        v = 0_u64 if negative?
        return false if v <= 1
        return true if v == 2 || v == 3
        return false if v.even?
        return false if v % 3 == 0
      else
        return false if negative?
        return false if even?
        return false if divisible_by?(3)
      end

      # Write self-1 = 2^r * d
      one = BigInt.new(1)
      self_minus_1 = self - one
      r = self_minus_1.trailing_zeros_count.to_i32
      d = self_minus_1 >> r

      two = BigInt.new(2)

      # Deterministic witnesses sufficient for numbers < 3.3e24
      witnesses = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37]

      witnesses.each do |a_int|
        a = BigInt.new(a_int)
        next if a >= self
        x = a.pow_mod(d, self)
        next if (x.abs_size == 1 && x.@limbs[0] == 1_u64 && !x.negative?) || x == self_minus_1
        found = false
        (r - 1).times do
          x = x.pow_mod(two, self)
          if x == self_minus_1
            found = true
            break
          end
        end
        return false unless found
      end
      true
    end

    # --- Conversion ---

    # Converts the absolute value to a byte array. Raises for negative values.
    # Uses big-endian byte order by default (most-significant byte first).
    #
    # ```
    # BigNumber::BigInt.new(256).to_bytes              # => Bytes[1, 0]
    # BigNumber::BigInt.new(256).to_bytes(big_endian: false) # => Bytes[0, 1]
    # ```
    def to_bytes(big_endian : Bool = true) : Bytes
      raise ArgumentError.new("Cannot convert negative BigInt to bytes") if negative?
      if zero?
        return Bytes.new(1, 0_u8)
      end

      n = abs_size
      # Total bytes needed
      top_limb = @limbs[n - 1]
      top_bytes = (64 - top_limb.leading_zeros_count.to_i32 + 7) // 8
      total = (n - 1) * 8 + top_bytes
      bytes = Bytes.new(total)

      # Write in little-endian limb order first, then reverse if big_endian
      pos = 0
      (n - 1).times do |i|
        limb = @limbs[i]
        8.times do |b|
          bytes[pos] = (limb >> (b * 8)).to_u8!
          pos += 1
        end
      end
      # Top limb (only top_bytes bytes)
      top_bytes.times do |b|
        bytes[pos] = (top_limb >> (b * 8)).to_u8!
        pos += 1
      end

      if big_endian
        bytes.reverse!
      end
      bytes
    end

    # Creates a `BigInt` from a byte array. Assumes unsigned (non-negative) value.
    # Uses big-endian byte order by default.
    #
    # ```
    # BigNumber::BigInt.from_bytes(Bytes[1, 0]) # => 256
    # ```
    def self.from_bytes(bytes : Bytes, big_endian : Bool = true) : BigInt
      # Strip leading zeros
      start = 0
      if big_endian
        while start < bytes.size - 1 && bytes[start] == 0
          start += 1
        end
      else
        last = bytes.size - 1
        while last > 0 && bytes[last] == 0
          last -= 1
        end
        # Work with a trimmed slice
        bytes = bytes[0..last]
        start = 0
      end

      effective = big_endian ? bytes[start..] : bytes[start..]
      return BigInt.new if effective.size == 1 && effective[0] == 0

      n_limbs = (effective.size + 7) // 8
      result = BigInt.new
      result.ensure_capacity(n_limbs)

      n_limbs.times do |li|
        limb = 0_u64
        8.times do |b|
          byte_idx = if big_endian
                       effective.size - 1 - (li * 8 + b)
                     else
                       li * 8 + b
                     end
          break if byte_idx < 0 || byte_idx >= effective.size
          limb |= effective[byte_idx].to_u64 << (b * 8)
        end
        result.@limbs[li] = limb
      end
      result.set_size(n_limbs)
      result.normalize!
      result
    end

    # Returns the decimal string representation.
    def to_s : String
      to_s(10)
    end

    # Returns the string representation in the given *base* (2 to 36).
    # Uses divide-and-conquer O(n*log^2 n) conversion for >= 50 limbs,
    # otherwise simple O(n^2) repeated division.
    #
    # ```
    # BigNumber::BigInt.new(255).to_s(16) # => "ff"
    # ```
    def to_s(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : String
      String.build do |io|
        to_s(io, base, precision: precision, upcase: upcase)
      end
    end

    # Writes the decimal string representation to *io*.
    def to_s(io : IO) : Nil
      to_s(io, 10)
    end

    # Threshold (in limbs) above which divide-and-conquer base conversion is used.
    DC_TO_S_THRESHOLD = 50

    # Writes the string representation in *base* to *io*. Dispatches to
    # single-limb fast path, `simple_to_s`, or `dc_to_s` based on size.
    def to_s(io : IO, base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Nil
      raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36
      if zero?
        io << '-' if @size < 0
        pad = Math.max(precision.to_i32, 1)
        pad.times { io << '0' }
        return
      end
      io << '-' if negative?

      n = abs_size
      if n == 1 && precision <= 1
        # Single-limb fast path: use Crystal's built-in integer-to-string
        s = @limbs[0].to_s(base)
        io << (upcase ? s.upcase : s)
      elsif n >= DC_TO_S_THRESHOLD
        BigInt.dc_to_s(io, @limbs, n, base.to_i32, precision.to_i32, upcase)
      else
        BigInt.simple_to_s(io, @limbs, n, base.to_i32, precision.to_i32, upcase)
      end
    end

    # Simple O(n^2) base conversion for numbers below `DC_TO_S_THRESHOLD` limbs.
    # Extracts digits in chunks: divides by `base^chunk_size` to get multiple
    # digits at once, then extracts individual digits from the remainder.
    protected def self.simple_to_s(io : IO, limbs : Pointer(Limb), size : Int32, base : Int32, precision : Int32, upcase : Bool)
      tmp = Pointer(Limb).malloc(size)
      tmp.copy_from(limbs, size)
      tmp_size = size

      chunk_size, chunk_base = chunk_params(base)

      # Pre-allocate digit buffer
      max_digits = (size.to_f64 * 64.0 * Math.log(2.0) / Math.log(base.to_f64)).to_i32 + 2
      max_digits = Math.max(max_digits, precision)
      buf = Pointer(UInt8).malloc(max_digits)
      pos = max_digits - 1

      while tmp_size > 0
        # Extract chunk_size digits at once by dividing by chunk_base
        rem = limbs_div_rem_1(tmp, tmp, tmp_size, chunk_base)
        while tmp_size > 0 && tmp[tmp_size - 1] == 0
          tmp_size -= 1
        end
        # Extract individual digits from rem
        if tmp_size > 0
          # Not the last chunk — emit exactly chunk_size digits (with leading zeros)
          chunk_size.times do
            buf[pos] = (rem % base.to_u64).to_u8
            rem = rem // base.to_u64
            pos -= 1
          end
        else
          # Last chunk — only emit significant digits
          while rem > 0 && pos >= 0
            buf[pos] = (rem % base.to_u64).to_u8
            rem = rem // base.to_u64
            pos -= 1
          end
        end
      end

      # Fill leading zeros for precision
      while (max_digits - 1 - pos) < precision
        buf[pos] = 0_u8
        pos -= 1
      end

      start = pos + 1
      i = start
      while i < max_digits
        c = digit_to_char(buf[i])
        io << (upcase ? c.upcase : c)
        i += 1
      end
    end

    # Divide-and-conquer base conversion: O(n*log^2 n).
    # Precomputes a table of squaring powers of base, splits the number in half by
    # dividing by a power of base, and recursively converts each half.
    # Power table is cached in `@@power_cache` across calls for the same base.
    protected def self.dc_to_s(io : IO, limbs : Pointer(Limb), size : Int32, base : Int32, precision : Int32, upcase : Bool)
      # Estimate digit count: digits ≈ bit_length * log(2)/log(base)
      top = limbs[size - 1]
      bit_len = (size - 1) * 64 + (64 - top.leading_zeros_count.to_i32)
      est_digits = (bit_len.to_f64 * Math.log(2.0) / Math.log(base.to_f64)).to_i32 + 2

      # Precompute base powers (cached across calls for same base)
      powers = precompute_base_powers(base, est_digits)

      # Allocate digit buffer (filled right-to-left with leading zeros)
      buf = Pointer(UInt8).malloc(est_digits)
      buf_len = est_digits
      est_digits.times { |i| buf[i] = 0_u8 }

      # Pre-allocate division scratch (reused across all recursive levels).
      # Largest division is at top level: size + max_divisor_size + 1.
      div_scratch = Pointer(Limb).malloc(2 * size + 2)

      # Copy limbs into working buffer
      np = Pointer(Limb).malloc(size)
      np.copy_from(limbs, size)

      # Recursively fill buffer
      dc_to_s_recurse_raw(buf, buf_len, np, size, base, powers, powers.size - 1, div_scratch)

      # Skip leading zeros (but respect precision)
      start = 0
      while start < buf_len - 1 && buf[start] == 0 && (buf_len - start) > precision
        start += 1
      end

      i = start
      while i < buf_len
        c = digit_to_char((buf + i).value)
        io << (upcase ? c.upcase : c)
        i += 1
      end
    end

    # Cached base power tables keyed by base. Each entry is an array of
    # squaring powers: `[base^chunk, base^(2*chunk), base^(4*chunk), ...]`.
    @@power_cache = Hash(Int32, Array(BigInt)).new

    # Precomputes squaring powers of base for divide-and-conquer base conversion.
    # Each `power[i]` covers `2^i * chunk_size` digits. Results are cached in
    # `@@power_cache` and extended as needed for larger numbers.
    protected def self.precompute_base_powers(base : Int32, max_digits : Int32) : Array(BigInt)
      chunk_size, _ = chunk_params(base)

      cached = @@power_cache[base]?
      if cached
        # Check if we have enough levels
        digits_covered = chunk_size * (1 << cached.size)
        if digits_covered >= max_digits
          return cached
        end
        # Extend the existing table
        p = cached.last
        while digits_covered < max_digits
          p = p * p
          cached << p
          digits_covered *= 2
        end
        return cached
      end

      # Build from scratch
      powers = [] of BigInt
      p = BigInt.new(base) ** chunk_size
      powers << p
      digits_covered = chunk_size
      while digits_covered * 2 < max_digits
        p = p * p
        powers << p
        digits_covered *= 2
      end
      @@power_cache[base] = powers
      powers
    end

    # Recursive workhorse for divide-and-conquer base conversion.
    # Splits `np[0..nn-1]` by dividing by `powers[level]`, writes high digits
    # to `buf[0..hi_digits-1]` and low digits to `buf[hi_digits..]`.
    # Falls back to simple extraction when `level < 0` or `nn < DC_TO_S_THRESHOLD`.
    # *div_scratch* is pre-allocated and shared across all recursive levels.
    protected def self.dc_to_s_recurse_raw(buf : Pointer(UInt8), buf_len : Int32,
                                           np : Pointer(Limb), nn : Int32,
                                           base : Int32, powers : Array(BigInt), level : Int32,
                                           div_scratch : Pointer(Limb))
      # Base case: small enough for batch digit extraction
      if level < 0 || nn < DC_TO_S_THRESHOLD
        return if nn <= 0 # buf already zero-filled

        chunk_size, chunk_base = chunk_params(base)
        # Work directly on a copy (np may be shared/reused by caller)
        tmp = Pointer(Limb).malloc(nn)
        tmp.copy_from(np, nn)
        tmp_size = nn
        pos = buf_len - 1

        while tmp_size > 0 && pos >= 0
          rem = limbs_div_rem_1(tmp, tmp, tmp_size, chunk_base)
          while tmp_size > 0 && tmp[tmp_size - 1] == 0
            tmp_size -= 1
          end
          if tmp_size > 0
            chunk_size.times do
              break if pos < 0
              buf[pos] = (rem % base.to_u64).to_u8
              rem = rem // base.to_u64
              pos -= 1
            end
          else
            while rem > 0 && pos >= 0
              buf[pos] = (rem % base.to_u64).to_u8
              rem = rem // base.to_u64
              pos -= 1
            end
          end
        end
        return
      end

      divisor = powers[level]
      dn = divisor.abs_size
      # If num < divisor, skip this level
      if nn < dn || (nn == dn && limbs_cmp(np, nn, divisor.@limbs, dn) < 0)
        dc_to_s_recurse_raw(buf, buf_len, np, nn, base, powers, level - 1, div_scratch)
        return
      end

      # Split: np = qp * divisor + rp (using raw limbs, sharing div_scratch)
      qn = nn - dn + 1
      qp = Pointer(Limb).malloc(qn)
      rp = Pointer(Limb).malloc(dn)
      limbs_div_rem(qp, rp, np, nn, divisor.@limbs, dn, div_scratch)
      # Normalize sizes
      while qn > 0 && qp[qn - 1] == 0
        qn -= 1
      end
      rn = dn
      while rn > 0 && rp[rn - 1] == 0
        rn -= 1
      end

      # The divisor covers chunk_size * 2^level digits → that's the size of the lower half
      chunk_size, _ = chunk_params(base)
      lo_digits = chunk_size * (1 << level)
      if lo_digits > buf_len
        lo_digits = buf_len
      end
      hi_digits = buf_len - lo_digits

      # Recurse on each half
      dc_to_s_recurse_raw(buf, hi_digits, qp, qn, base, powers, level - 1, div_scratch)
      dc_to_s_recurse_raw(buf + hi_digits, lo_digits, rp, rn, base, powers, level - 1, div_scratch)
    end

    # Writes the decimal representation to *io* (same as `to_s`).
    def inspect(io : IO) : Nil
      to_s(io, 10)
    end

    # --- Checked integer conversions ---
    # These methods convert to fixed-width integers with overflow checking.
    # The `!` variants wrap/truncate on overflow instead of raising.

    # Converts to `Int32`. Raises `OverflowError` if value doesn't fit.
    def to_i : Int32
      to_i32
    end

    # Wrapping conversion to `Int32` (truncates on overflow).
    def to_i! : Int32
      to_i32!
    end

    # Converts to `UInt32`. Raises `OverflowError` if value doesn't fit.
    def to_u : UInt32
      to_u32
    end

    # Wrapping conversion to `UInt32` (truncates on overflow).
    def to_u! : UInt32
      to_u32!
    end

    {% for info in [{Int8, "i8"}, {Int16, "i16"}, {Int32, "i32"}, {Int64, "i64"}, {Int128, "i128"}] %}
      def to_{{info[1].id}} : {{info[0]}}
        val = to_i128_internal
        if val < {{info[0]}}::MIN.to_i128 || val > {{info[0]}}::MAX.to_i128
          raise OverflowError.new("BigInt too large for {{info[0]}}")
        end
        val.to_{{info[1].id}}!
      end

      def to_{{info[1].id}}! : {{info[0]}}
        return {{info[0]}}.new(0) if zero?
        {% if info[1] == "i128" %}
          to_i128_internal.to_i128!
        {% else %}
          val = @limbs[0].to_{{info[1].id}}!
          negative? ? (0.to_{{info[1].id}}! &- val) : val
        {% end %}
      end
    {% end %}

    {% for info in [{UInt8, "u8"}, {UInt16, "u16"}, {UInt32, "u32"}, {UInt64, "u64"}, {UInt128, "u128"}] %}
      def to_{{info[1].id}} : {{info[0]}}
        raise OverflowError.new("Negative BigInt") if negative?
        val = to_u128_internal
        if val > {{info[0]}}::MAX.to_u128
          raise OverflowError.new("BigInt too large for {{info[0]}}")
        end
        val.to_{{info[1].id}}!
      end

      def to_{{info[1].id}}! : {{info[0]}}
        return {{info[0]}}.new(0) if zero?
        {% if info[1] == "u128" %}
          to_u128_internal.to_u128!
        {% else %}
          val = @limbs[0].to_{{info[1].id}}!
          negative? ? (0.to_{{info[1].id}}! &- val) : val
        {% end %}
      end
    {% end %}

    # Converts to `Float64`. May lose precision for large values; returns infinity
    # if the magnitude exceeds `Float64::MAX`.
    def to_f : Float64
      to_f64
    end

    # :ditto:
    def to_f! : Float64
      to_f64
    end

    # Converts to `Float32` via `Float64`.
    def to_f32 : Float32
      to_f64.to_f32
    end

    # :ditto:
    def to_f32! : Float32
      to_f64.to_f32
    end

    # Converts to `Float64` using the top two limbs for correct rounding at any size.
    def to_f64 : Float64
      return 0.0 if zero?
      n = abs_size
      if n == 1
        return negative? ? -@limbs[0].to_f64 : @limbs[0].to_f64
      end
      # Use top 2 limbs + exponent for correct rounding at any size.
      # Float64 has 53 bits of mantissa; 2 limbs = 128 bits is more than enough.
      hi = @limbs[n - 1].to_f64
      lo = @limbs[n - 2].to_f64
      # hi * 2^64 + lo, then shift by the remaining limbs
      result = hi * (UInt64::MAX.to_f64 + 1.0) + lo
      # Scale by 2^(64*(n-2)) for the lower limbs we skipped
      exp = (n - 2) * 64
      result = result * 2.0 ** exp
      negative? ? -result : result
    end

    # :ditto:
    def to_f64! : Float64
      to_f64
    end

    # Returns `self` (no-op identity conversion).
    def to_big_i : BigInt
      self
    end

    # Converts to `BigFloat` with the given precision (in bits).
    def to_big_f(*, precision : Int32 = BigFloat.default_precision) : BigFloat
      BigFloat.new(self, precision: precision)
    end

    # Converts to `BigRational` with denominator 1.
    def to_big_r : BigRational
      BigRational.new(self)
    end

    # Converts to `BigDecimal` with scale 0.
    def to_big_d : BigDecimal
      BigDecimal.new(self)
    end

    # Returns the digits in *base* as an `Array(Int32)`, least-significant first.
    # Raises for negative numbers or invalid base.
    #
    # ```
    # BigNumber::BigInt.new(123).digits # => [3, 2, 1]
    # ```
    def digits(base : Int = 10) : Array(Int32)
      raise ArgumentError.new("Can't request digits of negative number") if negative?
      raise ArgumentError.new("Invalid base #{base}") unless base >= 2
      return [0] if zero?

      result = [] of Int32
      tmp = dup_value
      b = BigInt.new(base)
      while !tmp.zero?
        q, r = tmp.tdiv_rem(b)
        result << r.to_i32
        tmp = q
      end
      result
    end

    # --- Misc ---

    # Returns the smallest power of two >= `self`. Returns 1 for non-positive values.
    def next_power_of_two : BigInt
      return BigInt.new(1) if @size <= 0
      popcount == 1 ? dup_value : BigInt.new(1) << bit_length
    end

    # Divides out all factors of *number* from `|self|`.
    # Returns `{remaining, count}` where `count` is how many times *number* divides evenly.
    def factor_by(number : Int) : {BigInt, UInt64}
      raise ArgumentError.new("Can't factor by #{number}") if number <= 1
      d = BigInt.new(number)
      count = 0_u64
      current = self.abs
      while !current.zero?
        q, r = current.tdiv_rem(d)
        break unless r.zero?
        current = q
        count += 1
      end
      {current, count}
    end

    # Returns a deep copy.
    def clone : BigInt
      dup_value
    end

    # --- Protected helpers exposed to other BigInt methods ---

    # Creates a `BigInt` with pre-allocated limb storage of the given capacity.
    # Value is zero until limbs are filled and `set_size` is called.
    protected def initialize(*, capacity : Int32)
      @limbs = Pointer(Limb).malloc(capacity)
      @alloc = capacity
      @size = 0
    end

    # Sets the signed size directly. Positive = positive, negative = negative.
    protected def set_size(@size : Int32)
    end

    # Returns a raw pointer to the limb array.
    protected def limbs_ptr : Pointer(Limb)
      @limbs
    end

    # Negates in place by flipping the sign of `@size`.
    protected def negate!
      @size = -@size
    end

    # Makes the value non-negative in place.
    protected def abs!
      @size = abs_size
    end

    # Ensures the limb array can hold at least *n* limbs. Doubles capacity on growth.
    protected def ensure_capacity(n : Int32)
      return if @alloc >= n
      new_alloc = Math.max(n, @alloc * 2)
      new_alloc = Math.max(new_alloc, 1)
      new_limbs = Pointer(Limb).malloc(new_alloc)
      if @alloc > 0 && !@limbs.null?
        new_limbs.copy_from(@limbs, abs_size)
      end
      @limbs = new_limbs
      @alloc = new_alloc
    end

    # Strips leading zero limbs, adjusting `@size` while preserving sign.
    protected def normalize!
      n = @size < 0 ? -@size : @size
      while n > 0 && @limbs[n - 1] == 0
        n -= 1
      end
      @size = @size < 0 ? -n : n
    end

    # Creates a deep copy of this `BigInt` with independent limb storage.
    protected def dup_value : BigInt
      n = abs_size
      return BigInt.new if n == 0
      result = BigInt.new(capacity: n)
      result.@limbs.copy_from(@limbs, n)
      result.set_size(@size)
      result
    end

    # --- Private ---

    # Extracts value as `Int128` from the bottom two limbs (no range check).
    private def to_i128_internal : Int128
      return 0_i128 if zero?
      n = abs_size
      val = @limbs[0].to_u128
      val |= @limbs[1].to_u128 << 64 if n >= 2
      negative? ? (0_i128 &- val.to_i128!) : val.to_i128!
    end

    # Extracts magnitude as `UInt128` from the bottom two limbs (no range check).
    private def to_u128_internal : UInt128
      return 0_u128 if zero?
      n = abs_size
      val = @limbs[0].to_u128
      val |= @limbs[1].to_u128 << 64 if n >= 2
      val
    end

    # Applies a bitwise operation (AND, OR, XOR) with two's complement semantics.
    # For negative x, two's complement is `~(|x| - 1)`. Both-positive case uses
    # a fast path without two's complement conversion.
    private def bitwise_op(other : BigInt, op : Symbol) : BigInt
      # Both positive: direct limb-by-limb
      if !negative? && !other.negative?
        return bitwise_pos_pos(other, op)
      end

      # Use the identity: -x in two's complement = ~(x-1)
      # Convert to two's complement, apply op, convert back.
      #
      # Result sign (from infinite sign bits):
      # AND: neg only if both neg
      # OR:  neg if either neg
      # XOR: neg if exactly one neg
      result_negative = case op
                         when :and then negative? && other.negative?
                         when :or  then negative? || other.negative?
                         when :xor then negative? ^ other.negative?
                         else           false
                         end

      an = abs_size
      bn = other.abs_size
      max_n = Math.max(an, bn) + 1 # +1 for possible carry

      # Build two's complement limb arrays for each operand
      a_tc = Pointer(Limb).malloc(max_n)
      b_tc = Pointer(Limb).malloc(max_n)

      fill_twos_complement(a_tc, max_n)
      other.fill_twos_complement(b_tc, max_n)

      # Apply operation limb-by-limb
      r_tc = Pointer(Limb).malloc(max_n)
      max_n.times do |i|
        r_tc[i] = case op
                  when :and then a_tc[i] & b_tc[i]
                  when :or  then a_tc[i] | b_tc[i]
                  when :xor then a_tc[i] ^ b_tc[i]
                  else           0_u64
                  end
      end

      # Convert result back from two's complement
      result = BigInt.new(capacity: max_n)
      if result_negative
        # Result is negative: r_tc is two's complement of magnitude
        # magnitude = ~r_tc + 1 (negate two's complement)
        max_n.times { |i| r_tc[i] = ~r_tc[i] }
        # Add 1
        carry = 1_u64
        max_n.times do |i|
          sum = r_tc[i].to_u128 &+ carry.to_u128
          r_tc[i] = sum.to_u64!
          carry = (sum >> 64).to_u64!
        end
        result.@limbs.copy_from(r_tc, max_n)
        result.set_size(-max_n)
        result.normalize!
      else
        result.@limbs.copy_from(r_tc, max_n)
        result.set_size(max_n)
        result.normalize!
      end
      result
    end

    # Fast-path bitwise operation when both operands are non-negative (no two's complement needed).
    private def bitwise_pos_pos(other : BigInt, op : Symbol) : BigInt
      an = abs_size
      bn = other.abs_size
      max_n = Math.max(an, bn)
      result = BigInt.new(capacity: max_n)
      max_n.times do |i|
        a_limb = i < an ? @limbs[i] : 0_u64
        b_limb = i < bn ? other.@limbs[i] : 0_u64
        result.@limbs[i] = case op
                           when :and then a_limb & b_limb
                           when :or  then a_limb | b_limb
                           when :xor then a_limb ^ b_limb
                           else           0_u64
                           end
      end
      result.set_size(max_n)
      result.normalize!
      result
    end

    # Fill buffer with two's complement representation of self, padded to n limbs.
    # Positive: just copy magnitude, zero-extend.
    # Negative: ~(|self| - 1), sign-extend with 0xFF..FF.
    protected def fill_twos_complement(buf : Pointer(Limb), n : Int32)
      an = abs_size
      if !negative?
        an.times { |i| buf[i] = @limbs[i] }
        (an...n).each { |i| buf[i] = 0_u64 }
      else
        # Compute ~(magnitude - 1)
        # First: magnitude - 1
        borrow = 1_u64
        an.times do |i|
          diff = @limbs[i].to_u128 &- borrow.to_u128
          buf[i] = ~diff.to_u64!
          borrow = (diff >> 127) != 0 ? 1_u64 : 0_u64
        end
        # Sign extend
        (an...n).each { |i| buf[i] = Limb::MAX }
      end
    end

    # Initializes limbs from a `UInt128` magnitude value.
    private def set_from_unsigned(mag : UInt128)
      lo = mag.to_u64!
      hi = (mag >> 64).to_u64!
      if hi != 0
        ensure_capacity(2)
        @limbs[0] = lo
        @limbs[1] = hi
        @size = 2
      elsif lo != 0
        ensure_capacity(1)
        @limbs[0] = lo
        @size = 1
      end
    end

    # Adds the magnitudes of `self` and *other*, returning a new `BigInt` with the given sign.
    protected def add_magnitudes(other : BigInt, result_negative : Bool = @size < 0) : BigInt
      an = abs_size
      bn = other.abs_size
      ap = @limbs
      bp = other.@limbs
      # Ensure an >= bn for the add
      if an < bn
        an, bn = bn, an
        ap, bp = bp, ap
      end
      result = BigInt.new(capacity: an + 1)
      carry = BigInt.limbs_add(result.@limbs, ap, an, bp, bn)
      if carry != 0
        result.@limbs[an] = carry
        result.set_size(an + 1)
      else
        result.set_size(an)
      end
      if result_negative
        result.set_size(-result.@size)
      end
      result.normalize!
      result
    end

    # Subtracts magnitudes, determining result sign from which is larger.
    private def sub_magnitudes(other : BigInt) : BigInt
      an = abs_size
      bn = other.abs_size
      cmp = BigInt.limbs_cmp(@limbs, an, other.@limbs, bn)
      if cmp == 0
        return BigInt.new # equal magnitudes = zero
      end
      if cmp > 0
        # |self| > |other|
        result = BigInt.new(capacity: an)
        BigInt.limbs_sub(result.@limbs, @limbs, an, other.@limbs, bn)
        result.set_size(an)
        result.set_size(-result.@size) if @size < 0
      else
        # |self| < |other|
        result = BigInt.new(capacity: bn)
        BigInt.limbs_sub(result.@limbs, other.@limbs, bn, @limbs, an)
        result.set_size(bn)
        result.set_size(-result.@size) if @size >= 0
      end
      result.normalize!
      result
    end

    # --- Class-level limb array operations ---
    # Low-level operations on raw limb pointers. These form the computational
    # core of all arithmetic. ARM64 builds use inline assembly for inner loops;
    # other architectures use UInt128-based fallbacks.

    # Compares two unsigned limb arrays. Returns -1, 0, or 1.
    protected def self.limbs_cmp(ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32) : Int32
      return 1 if an > bn
      return -1 if an < bn
      i = an - 1
      while i >= 0
        return 1 if ap[i] > bp[i]
        return -1 if ap[i] < bp[i]
        i -= 1
      end
      0
    end

    # Adds two unsigned limb arrays: `rp = ap + bp`. Requires `an >= bn`.
    # Returns carry (0 or 1). Uses ARM64 `adds`/`adc` inline assembly when available.
    protected def self.limbs_add(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32) : Limb
      carry = 0_u64
      i = 0
      {% if flag?(:aarch64) %}
        while i < bn
          a = ap[i]
          b = bp[i]
          r = 0_u64
          c_out = 0_u64
          asm(
            "adds  $0, $2, $3   \n" \
            "adc   $1, xzr, xzr \n" \
            "adds  $0, $0, $4   \n" \
            "adc   $1, $1, xzr  \n"
            : "=&r"(r), "=&r"(c_out)
            : "r"(a), "r"(b), "r"(carry)
            : "cc"
          )
          rp[i] = r
          carry = c_out
          i += 1
        end
        while i < an
          a = ap[i]
          r = 0_u64
          c_out = 0_u64
          asm(
            "adds  $0, $2, $3   \n" \
            "adc   $1, xzr, xzr \n"
            : "=&r"(r), "=&r"(c_out)
            : "r"(a), "r"(carry)
            : "cc"
          )
          rp[i] = r
          carry = c_out
          i += 1
        end
      {% else %}
        while i < bn
          sum = ap[i].to_u128 &+ bp[i].to_u128 &+ carry.to_u128
          rp[i] = sum.to_u64!
          carry = (sum >> 64).to_u64!
          i += 1
        end
        while i < an
          sum = ap[i].to_u128 &+ carry.to_u128
          rp[i] = sum.to_u64!
          carry = (sum >> 64).to_u64!
          i += 1
        end
      {% end %}
      carry
    end

    # Subtracts two unsigned limb arrays: `rp = ap - bp`. Requires `ap >= bp` in magnitude
    # and `an >= bn`. Returns borrow. Uses ARM64 `subs`/`cset`/`cinc` inline assembly.
    protected def self.limbs_sub(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32) : Limb
      borrow = 0_u64
      i = 0
      {% if flag?(:aarch64) %}
        while i < bn
          a = ap[i]
          b = bp[i]
          r = 0_u64
          b_out = 0_u64
          asm(
            "subs  $0, $2, $3   \n" \
            "cset  $1, cc        \n" \
            "subs  $0, $0, $4   \n" \
            "cinc  $1, $1, cc    \n"
            : "=&r"(r), "=&r"(b_out)
            : "r"(a), "r"(b), "r"(borrow)
            : "cc"
          )
          rp[i] = r
          borrow = b_out
          i += 1
        end
        while i < an
          a = ap[i]
          r = 0_u64
          b_out = 0_u64
          asm(
            "subs  $0, $2, $3   \n" \
            "cset  $1, cc        \n"
            : "=&r"(r), "=&r"(b_out)
            : "r"(a), "r"(borrow)
            : "cc"
          )
          rp[i] = r
          borrow = b_out
          i += 1
        end
      {% else %}
        while i < bn
          b1 = ap[i] < bp[i] ? 1_u64 : 0_u64
          d = ap[i] &- bp[i]
          b2 = d < borrow ? 1_u64 : 0_u64
          rp[i] = d &- borrow
          borrow = b1 &+ b2
          i += 1
        end
        while i < an
          b = ap[i] < borrow ? 1_u64 : 0_u64
          rp[i] = ap[i] &- borrow
          borrow = b
          i += 1
        end
      {% end %}
      borrow
    end

    # Adds a single limb to a limb array: `rp = ap + b`. Returns carry.
    # Uses ARM64 inline assembly when available.
    protected def self.limbs_add_1(rp : Pointer(Limb), ap : Pointer(Limb), n : Int32, b : Limb) : Limb
      {% if flag?(:aarch64) %}
        carry = b
        i = 0
        while i < n
          a = ap[i]
          r = 0_u64
          c_out = 0_u64
          asm(
            "adds  $0, $2, $3   \n" \
            "adc   $1, xzr, xzr \n"
            : "=&r"(r), "=&r"(c_out)
            : "r"(a), "r"(carry)
            : "cc"
          )
          rp[i] = r
          carry = c_out
          i += 1
        end
        carry
      {% else %}
        carry = b.to_u128
        i = 0
        while i < n
          sum = ap[i].to_u128 &+ carry
          rp[i] = sum.to_u64!
          carry = sum >> 64
          i += 1
        end
        carry.to_u64!
      {% end %}
    end

    # Multiplies a limb array by a single limb: `rp = ap * b`. Returns carry.
    # Uses ARM64 `mul`/`umulh` inline assembly when available.
    protected def self.limbs_mul_1(rp : Pointer(Limb), ap : Pointer(Limb), n : Int32, b : Limb) : Limb
      carry = 0_u64
      i = 0
      {% if flag?(:aarch64) %}
        while i < n
          x_ap = ap[i]
          lo = 0_u64
          hi = 0_u64
          asm(
            "mul   $0, $3, $4    \n" \
            "umulh $1, $3, $4    \n" \
            "adds  $0, $0, $2   \n" \
            "adc   $1, $1, xzr  \n"
            : "=&r"(lo), "=&r"(hi)
            : "r"(carry), "r"(x_ap), "r"(b)
            : "cc"
          )
          rp[i] = lo
          carry = hi
          i += 1
        end
      {% else %}
        carry_128 = 0_u128
        while i < n
          prod = ap[i].to_u128 &* b.to_u128 &+ carry_128
          rp[i] = prod.to_u64!
          carry_128 = prod >> 64
          i += 1
        end
        carry = carry_128.to_u64!
      {% end %}
      carry
    end

    # Fused multiply-add: `rp += ap * b`. Returns carry out.
    # Core inner loop for schoolbook multiplication.
    # Uses ARM64 `mul`/`umulh`/`adds`/`adc` inline assembly when available.
    protected def self.limbs_addmul_1(rp : Pointer(Limb), ap : Pointer(Limb), n : Int32, b : Limb) : Limb
      carry = 0_u64
      i = 0
      {% if flag?(:aarch64) %}
        while i < n
          x_ap = ap[i]
          x_rp = rp[i]
          lo = 0_u64
          hi = 0_u64
          asm(
            "mul   $0, $4, $5    \n" \
            "umulh $1, $4, $5    \n" \
            "adds  $0, $0, $2   \n" \
            "adc   $1, $1, xzr  \n" \
            "adds  $0, $0, $3   \n" \
            "adc   $1, $1, xzr  \n"
            : "=&r"(lo), "=&r"(hi)
            : "r"(x_rp), "r"(carry), "r"(x_ap), "r"(b)
            : "cc"
          )
          rp[i] = lo
          carry = hi
          i += 1
        end
      {% else %}
        carry_128 = 0_u128
        while i < n
          prod = ap[i].to_u128 &* b.to_u128 &+ rp[i].to_u128 &+ carry_128
          rp[i] = prod.to_u64!
          carry_128 = prod >> 64
          i += 1
        end
        carry = carry_128.to_u64!
      {% end %}
      carry
    end

    # Fused multiply-subtract: `rp -= ap * b`. Returns borrow out.
    # Core inner loop for Knuth Algorithm D division.
    # Uses ARM64 inline assembly when available.
    protected def self.limbs_submul_1(rp : Pointer(Limb), ap : Pointer(Limb), n : Int32, b : Limb) : Limb
      borrow = 0_u64
      i = 0
      {% if flag?(:aarch64) %}
        while i < n
          x_ap = ap[i]
          x_rp = rp[i]
          lo = 0_u64
          new_borrow = 0_u64
          asm(
            "mul   $0, $4, $5    \n" \
            "umulh $1, $4, $5    \n" \
            "adds  $0, $0, $3   \n" \
            "adc   $1, $1, xzr  \n" \
            "subs  $0, $2, $0   \n" \
            "cinc  $1, $1, cc    \n"
            : "=&r"(lo), "=&r"(new_borrow)
            : "r"(x_rp), "r"(borrow), "r"(x_ap), "r"(b)
            : "cc"
          )
          rp[i] = lo
          borrow = new_borrow
          i += 1
        end
      {% else %}
        borrow_128 = 0_u128
        while i < n
          prod = ap[i].to_u128 &* b.to_u128 &+ borrow_128
          lo = prod.to_u64!
          old = rp[i]
          rp[i] = old &- lo
          borrow_128 = (prod >> 64) &+ (old < lo ? 1_u128 : 0_u128)
          i += 1
        end
        borrow = borrow_128.to_u64!
      {% end %}
      borrow
    end

    # Limb count threshold: schoolbook -> Karatsuba.
    KARATSUBA_THRESHOLD = 48
    # Limb count threshold: Karatsuba -> Toom-3 (effectively disabled; Karatsuba wins).
    TOOM3_THRESHOLD     = 10_000
    # Limb count threshold: Karatsuba -> NTT (Goldilocks prime).
    NTT_THRESHOLD       = 25_000

    # Top-level multiply dispatch. Requires `an >= bn > 0`. Result buffer `rp`
    # must not alias `ap` or `bp` and must have room for `an + bn` limbs.
    protected def self.limbs_mul(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32)
      if bn < KARATSUBA_THRESHOLD
        limbs_mul_schoolbook(rp, ap, an, bp, bn)
      elsif bn < NTT_THRESHOLD
        scratch = Pointer(Limb).malloc(karatsuba_scratch_size(an))
        limbs_mul_karatsuba(rp, ap, an, bp, bn, scratch)
      else
        limbs_mul_ntt(rp, ap, an, bp, bn)
      end
    end

    # Schoolbook (grade-school) multiplication: O(an * bn). Zeros the result
    # buffer then accumulates partial products via `limbs_addmul_1`.
    protected def self.limbs_mul_schoolbook(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32)
      (an + bn).times { |i| rp[i] = 0_u64 }
      i = 0
      while i < bn
        carry = limbs_addmul_1(rp + i, ap, an, bp[i])
        rp[i + an] = carry
        i += 1
      end
    end

    # Karatsuba multiplication: O(n^1.585). Splits operands at the midpoint,
    # computes z0 = a0*b0, z2 = a1*b1, z1 = (a0+a1)*(b0+b1) - z0 - z2,
    # and combines: result = z0 + z1*B^m + z2*B^(2m).
    # Falls back to schoolbook below `KARATSUBA_THRESHOLD` and handles
    # unbalanced operands (an >= 2*bn) by slicing into chunks.
    protected def self.limbs_mul_karatsuba(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32, scratch : Pointer(Limb))
      if bn < KARATSUBA_THRESHOLD
        limbs_mul_schoolbook(rp, ap, an, bp, bn)
        return
      end

      if an >= 2 * bn
        limbs_mul_unbalanced(rp, ap, an, bp, bn, scratch)
        return
      end

      # Split: a = a1*B^m + a0, b = b1*B^m + b0
      m = bn >> 1
      a0 = ap;       a0n = m
      a1 = ap + m;   a1n = an - m
      b0 = bp;       b0n = m
      b1 = bp + m;   b1n = bn - m

      # z0 = a0 * b0 → rp[0..2m-1]
      limbs_mul_karatsuba(rp, a0, a0n, b0, b0n, scratch)

      # Zero upper part of rp
      i = 2 * m
      while i < an + bn
        rp[i] = 0_u64
        i += 1
      end

      # z2 = a1 * b1 → rp[2m..]
      limbs_mul_karatsuba(rp + 2 * m, a1, a1n, b1, b1n, scratch)

      # z1 = (a0+a1)*(b0+b1) - z0 - z2
      # Layout in scratch: [t1 (m+2) | t2 (m+2) | t3 (2m+4) | recursive scratch]
      t1 = scratch
      t1n = Math.max(a0n, a1n) + 1
      t2 = scratch + t1n
      t2n = Math.max(b0n, b1n) + 1

      # t1 = a0 + a1
      if a0n >= a1n
        t1[a0n] = limbs_add(t1, a0, a0n, a1, a1n)
      else
        t1[a1n] = limbs_add(t1, a1, a1n, a0, a0n)
      end
      actual_t1n = t1n
      while actual_t1n > 0 && t1[actual_t1n - 1] == 0
        actual_t1n -= 1
      end
      actual_t1n = 1 if actual_t1n == 0

      # t2 = b0 + b1
      if b0n >= b1n
        t2[b0n] = limbs_add(t2, b0, b0n, b1, b1n)
      else
        t2[b1n] = limbs_add(t2, b1, b1n, b0, b0n)
      end
      actual_t2n = t2n
      while actual_t2n > 0 && t2[actual_t2n - 1] == 0
        actual_t2n -= 1
      end
      actual_t2n = 1 if actual_t2n == 0

      # t3 = t1 * t2, placed after t1 and t2 in scratch
      t3 = scratch + t1n + t2n
      t3n = actual_t1n + actual_t2n
      next_scratch = t3 + t3n
      if actual_t1n >= actual_t2n
        limbs_mul_karatsuba(t3, t1, actual_t1n, t2, actual_t2n, next_scratch)
      else
        limbs_mul_karatsuba(t3, t2, actual_t2n, t1, actual_t1n, next_scratch)
      end
      while t3n > 0 && t3[t3n - 1] == 0
        t3n -= 1
      end

      # t3 -= z0
      z0n = a0n + b0n
      while z0n > 0 && rp[z0n - 1] == 0
        z0n -= 1
      end
      limbs_sub(t3, t3, t3n, rp, z0n) if z0n > 0 && t3n >= z0n

      # t3 -= z2
      z2n = a1n + b1n
      while z2n > 0 && rp[2 * m + z2n - 1] == 0
        z2n -= 1
      end
      limbs_sub(t3, t3, t3n, rp + 2 * m, z2n) if z2n > 0 && t3n >= z2n

      # Trim t3
      while t3n > 0 && t3[t3n - 1] == 0
        t3n -= 1
      end

      # Add t3 at position m
      if t3n > 0
        limbs_add(rp + m, rp + m, an + bn - m, t3, t3n)
      end
    end

    # Handles unbalanced multiplication when `an >= 2*bn`. Slices the larger
    # operand into `bn`-sized chunks, multiplies each chunk by `bp`, and
    # accumulates results with proper offsets.
    protected def self.limbs_mul_unbalanced(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32, scratch : Pointer(Limb))
      # Zero the result
      (an + bn).times { |i| rp[i] = 0_u64 }

      # Use scratch for the chunk product buffer (needs 2*bn limbs)
      tmp = scratch
      inner_scratch = scratch + 2 * bn

      offset = 0
      remaining = an
      while remaining > 0
        chunk = Math.min(remaining, bn)
        # Dispatch to best algorithm for this chunk size
        if chunk >= bn
          limbs_mul_dispatch(tmp, ap + offset, chunk, bp, bn, inner_scratch)
        else
          limbs_mul_dispatch(tmp, bp, bn, ap + offset, chunk, inner_scratch)
        end
        product_size = chunk + bn
        limbs_add(rp + offset, rp + offset, an + bn - offset, tmp, product_size)
        offset += chunk
        remaining -= chunk
      end
    end

    # Internal dispatch for recursive multiply within Karatsuba/Toom-3.
    # Selects schoolbook, Karatsuba, or Toom-3 based on `bn`.
    protected def self.limbs_mul_dispatch(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32, scratch : Pointer(Limb))
      if bn < KARATSUBA_THRESHOLD
        limbs_mul_schoolbook(rp, ap, an, bp, bn)
      elsif bn < TOOM3_THRESHOLD
        limbs_mul_karatsuba(rp, ap, an, bp, bn, scratch)
      else
        limbs_mul_toom3(rp, ap, an, bp, bn, scratch)
      end
    end

    # Computes scratch buffer size needed for Karatsuba multiplication of *n* limbs.
    protected def self.karatsuba_scratch_size(n : Int32) : Int32
      # Each Karatsuba level needs ~4*(n/2+1) scratch plus recursive scratch.
      # S(n) = 4*(n/2+1) + S(n/2+1) ≈ 4n. Add 2*n for unbalanced multiply tmp buffer.
      Math.max(6 * n + 64, 256)
    end

    # Computes scratch buffer size needed for Toom-3 multiplication of *n* limbs.
    protected def self.toom3_scratch_size(n : Int32) : Int32
      # Toom-3 scratch layout (k = ceil(n/3), pn = 2*(k+1)):
      #   [w0 | w1 | wm1 | w2 | winf | ea | eb | interp_c2 | interp_t | interp_tmp8 | eval_tmp | recursive_scratch]
      #   5*pn + 2*(k+2) + 3*maxn + (k+2) + recursive
      # where maxn = 2*k+4.
      # Conservative: ~24n covers all buffers plus recursion.
      Math.max(24 * n + 512, 2048)
    end

    # Toom-Cook 3-way multiplication: O(n^1.465).
    # Splits each operand into 3 pieces of ~n/3 limbs, evaluates at 5 points
    # {0, 1, -1, 2, infinity}, performs 5 recursive multiplications, then recovers
    # coefficients via interpolation. Currently effectively disabled since
    # `TOOM3_THRESHOLD > NTT_THRESHOLD` in practice.
    protected def self.limbs_mul_toom3(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32, scratch : Pointer(Limb))
      if bn < TOOM3_THRESHOLD
        if bn < KARATSUBA_THRESHOLD
          limbs_mul_schoolbook(rp, ap, an, bp, bn)
        else
          limbs_mul_karatsuba(rp, ap, an, bp, bn, scratch)
        end
        return
      end

      if an >= 3 * bn
        limbs_mul_unbalanced(rp, ap, an, bp, bn, scratch)
        return
      end

      # Split into thirds: k = ceil(an/3) so both operands fit in 3 pieces of size k.
      # Using bn would leave a2 with up to an-2*ceil(bn/3) limbs, which overflows buffers.
      k = (an + 2) // 3

      # a = a2*B^(2k) + a1*B^k + a0
      a0 = ap;           a0n = Math.min(k, an)
      a1 = ap + k;       a1n = Math.min(k, Math.max(an - k, 0))
      a2 = ap + 2 * k;   a2n = Math.max(an - 2 * k, 0)

      # b = b2*B^(2k) + b1*B^k + b0
      b0 = bp;           b0n = Math.min(k, bn)
      b1 = bp + k;       b1n = Math.min(k, Math.max(bn - k, 0))
      b2 = bp + 2 * k;   b2n = Math.max(bn - 2 * k, 0)

      # Normalize piece sizes (strip leading zeros) so limbs_cmp works correctly
      # in evaluation functions. Without this, pieces with trailing zeros in the
      # original number (e.g. 10^8192) would have inflated sizes.
      while a0n > 0 && a0[a0n - 1] == 0; a0n -= 1; end
      while a1n > 0 && a1[a1n - 1] == 0; a1n -= 1; end
      while a2n > 0 && a2[a2n - 1] == 0; a2n -= 1; end
      while b0n > 0 && b0[b0n - 1] == 0; b0n -= 1; end
      while b1n > 0 && b1[b1n - 1] == 0; b1n -= 1; end
      while b2n > 0 && b2[b2n - 1] == 0; b2n -= 1; end

      # We need 5 product buffers in scratch, each up to 2*(k+1) limbs.
      # Layout: [w0 | w1 | wm1 | w2 | winf | ea | eb | interp_c2 | interp_t | interp_tmp8 | eval_tmp | recursive_scratch]
      pn = 2 * (k + 1)  # max product size
      maxn = 2 * k + 4   # max coefficient size for interpolation
      w0   = scratch
      w1   = scratch + pn
      wm1  = scratch + 2 * pn
      w2   = scratch + 3 * pn
      winf = scratch + 4 * pn

      # Evaluation temporaries
      ea = scratch + 5 * pn                    # k+2 limbs for evaluating a
      eb = scratch + 5 * pn + (k + 2)         # k+2 limbs for evaluating b
      # Interpolation temporaries (carved from scratch, not heap-allocated)
      interp_c2  = scratch + 5 * pn + 2 * (k + 2)
      interp_t   = interp_c2 + maxn
      interp_tmp = interp_t + maxn             # used for 8*winf and eval_at2 temp
      rec_scratch = interp_tmp + maxn

      # --- Evaluate at point 0: a(0) = a0, b(0) = b0 ---
      # W(0) = a0 * b0
      if a0n > 0 && b0n > 0
        toom3_mul_recurse(w0, a0, a0n, b0, b0n, rec_scratch)
        w0n = a0n + b0n
        while w0n > 0 && w0[w0n - 1] == 0; w0n -= 1; end
      else
        w0[0] = 0_u64
        w0n = 0
      end

      # --- Evaluate at point ∞: a(∞) = a2, b(∞) = b2 ---
      # W(∞) = a2 * b2
      if a2n > 0 && b2n > 0
        toom3_mul_recurse(winf, a2, a2n, b2, b2n, rec_scratch)
        winfn = a2n + b2n
        while winfn > 0 && winf[winfn - 1] == 0; winfn -= 1; end
      else
        winf[0] = 0_u64
        winfn = 0
      end

      # --- Evaluate at point 1: a(1) = a0+a1+a2, b(1) = b0+b1+b2 ---
      ean = toom3_eval_pos(ea, a0, a0n, a1, a1n, a2, a2n)
      ebn = toom3_eval_pos(eb, b0, b0n, b1, b1n, b2, b2n)
      toom3_mul_recurse(w1, ea, ean, eb, ebn, rec_scratch)
      w1n = ean + ebn
      while w1n > 0 && w1[w1n - 1] == 0; w1n -= 1; end

      # --- Evaluate at point -1: a(-1) = a0-a1+a2, b(-1) = b0-b1+b2 ---
      ea_neg = false
      eb_neg = false
      ean, ea_neg = toom3_eval_neg(ea, a0, a0n, a1, a1n, a2, a2n)
      ebn, eb_neg = toom3_eval_neg(eb, b0, b0n, b1, b1n, b2, b2n)
      toom3_mul_recurse(wm1, ea, ean, eb, ebn, rec_scratch)
      wm1n = ean + ebn
      while wm1n > 0 && wm1[wm1n - 1] == 0; wm1n -= 1; end
      wm1_neg = ea_neg ^ eb_neg  # product is negative if exactly one eval was negative

      # --- Evaluate at point 2: a(2) = a0+2*a1+4*a2, b(2) = b0+2*b1+4*b2 ---
      ean = toom3_eval_at2(ea, a0, a0n, a1, a1n, a2, a2n, interp_tmp)
      ebn = toom3_eval_at2(eb, b0, b0n, b1, b1n, b2, b2n, interp_tmp)
      toom3_mul_recurse(w2, ea, ean, eb, ebn, rec_scratch)
      w2n = ean + ebn
      while w2n > 0 && w2[w2n - 1] == 0; w2n -= 1; end

      # --- Interpolation ---
      # We have: w0=W(0), w1=W(1), wm1=W(-1) (with sign), w2=W(2), winf=W(∞)
      # Need to recover r0..r4 where result = r0 + r1*B^k + r2*B^(2k) + r3*B^(3k) + r4*B^(4k)
      #
      # r0 = w0
      # r4 = winf
      # r3 = (w2 - w1) / 3 - (wm1_adj) ... using standard Toom-3 interpolation sequence
      #
      # Standard sequence (Bodrato & Zanoni):
      # 1. r3 = (w2 - wm1) / 3
      # 2. r1 = (w1 - wm1) / 2
      # 3. r2 = wm1 - w0   (using the sign-adjusted wm1)
      # ... actually let me use the standard formulation carefully.
      #
      # Let W0=w0, W1=w1, Wn=wm1 (with sign), W2=w2, Wi=winf
      # The interpolation matrix inversion gives:
      #   r0 = W0
      #   r4 = Wi
      #   r3 = (W2 - Wn) / 3          (then: r3 = (r3 - W1) / 2 + 2*Wi)  -- wait, standard formulation
      #
      # Using the well-known Toom-3 interpolation (from "Improved Toom-Cook" / GMP docs):
      #   Step 1: r3 = (w2 - wm1) / 3
      #   Step 2: r1 = (w1 - wm1) / 2
      #   Step 3: r2 = w1 - w0   (where w1 here is W(1), wm1 is signed W(-1))
      #   ... no, I need to be precise.
      #
      # Correct standard Toom-3 interpolation:
      #   Given: w0 = r0, w1 = r0+r1+r2+r3+r4, wm1 = r0-r1+r2-r3+r4,
      #          w2 = r0+2r1+4r2+8r3+16r4, winf = r4
      #
      #   1. w3 = (w2 - wm1) / 3       = 2*r1 + 4*r2 + (8+16/3)*... no
      #
      # Let me just use the concrete formulas:
      #   r0 = w0
      #   r4 = winf
      #   t1 = (w1 + wm1) / 2          = r0 + r2 + r4
      #   t2 = w1 - w0                  = r1 + r2 + r3 + r4
      #   t3 = (w2 - wm1) / 3          = r1 + r2*5/3... no...
      #
      # OK let me use the standard concrete sequence properly:
      #   r0 = w0
      #   r4 = winf
      #   Then define:
      #     w1 := w1 - w0              = r1 + r2 + r3 + r4
      #     w2 := w2 - wm1             = 2*(r1 + r2 + ... ) ... hmm
      #
      # I'll implement it step by step from the standard Toom-3 interpolation.

      toom3_interpolate(rp, an + bn, k, w0, w0n, w1, w1n, wm1, wm1n, wm1_neg, w2, w2n, winf, winfn, interp_c2, interp_t, interp_tmp)
    end

    # Toom-3 evaluation at point 1: computes `ea = a0 + a1 + a2`. Returns result size.
    protected def self.toom3_eval_pos(ea : Pointer(Limb), a0 : Pointer(Limb), a0n : Int32, a1 : Pointer(Limb), a1n : Int32, a2 : Pointer(Limb), a2n : Int32) : Int32
      # ea = a0 + a1
      if a0n >= a1n
        carry = a1n > 0 ? limbs_add(ea, a0, a0n, a1, a1n) : (a0n.times { |i| ea[i] = a0[i] }; 0_u64)
        ean = a0n
      else
        carry = limbs_add(ea, a1, a1n, a0, a0n)
        ean = a1n
      end
      ea[ean] = carry
      ean += 1 if carry != 0

      # ea += a2
      if a2n > 0
        if ean >= a2n
          carry2 = limbs_add(ea, ea, ean, a2, a2n)
        else
          carry2 = limbs_add(ea, a2, a2n, ea, ean)
          ean = a2n
        end
        ea[ean] = carry2
        ean += 1 if carry2 != 0
      end

      while ean > 1 && ea[ean - 1] == 0; ean -= 1; end
      ean = 1 if ean == 0
      ean
    end

    # Toom-3 evaluation at point -1: computes `ea = a0 - a1 + a2`.
    # Returns `{size, negative}` since the result may be negative.
    protected def self.toom3_eval_neg(ea : Pointer(Limb), a0 : Pointer(Limb), a0n : Int32, a1 : Pointer(Limb), a1n : Int32, a2 : Pointer(Limb), a2n : Int32) : {Int32, Bool}
      # First compute t = a0 + a2
      if a0n >= a2n
        carry = a2n > 0 ? limbs_add(ea, a0, a0n, a2, a2n) : (a0n.times { |i| ea[i] = a0[i] }; 0_u64)
        tn = a0n
      else
        carry = limbs_add(ea, a2, a2n, a0, a0n)
        tn = a2n
      end
      ea[tn] = carry
      tn += 1 if carry != 0
      while tn > 1 && ea[tn - 1] == 0; tn -= 1; end

      # Now subtract a1: result = (a0 + a2) - a1
      neg = false
      if a1n == 0
        # result is just ea, positive
      else
        cmp = limbs_cmp(ea, tn, a1, a1n)
        if cmp >= 0
          limbs_sub(ea, ea, tn, a1, a1n)
        else
          # Need to compute a1 - (a0+a2), result is negative
          # Use ea as temp - we can overwrite since we're computing into ea
          limbs_sub(ea, a1, a1n, ea, tn)
          tn = a1n
          neg = true
        end
      end

      while tn > 1 && ea[tn - 1] == 0; tn -= 1; end
      tn = 1 if tn == 0
      {tn, neg}
    end

    # Toom-3 evaluation at point 2: computes `ea = a0 + 2*a1 + 4*a2`.
    # Uses *tmp* for shifted intermediates. Returns result size.
    protected def self.toom3_eval_at2(ea : Pointer(Limb), a0 : Pointer(Limb), a0n : Int32, a1 : Pointer(Limb), a1n : Int32, a2 : Pointer(Limb), a2n : Int32, tmp : Pointer(Limb)) : Int32
      # Start with a0
      if a0n > 0
        a0n.times { |i| ea[i] = a0[i] }
        ean = a0n
      else
        ea[0] = 0_u64
        ean = 1
      end

      # Add 2*a1 using provided temp buffer
      if a1n > 0
        top = limbs_lshift(tmp, a1, a1n, 1)
        tmpn = a1n
        if top != 0; tmp[tmpn] = top; tmpn += 1; end
        if ean >= tmpn
          c = limbs_add(ea, ea, ean, tmp, tmpn)
        else
          c = limbs_add(ea, tmp, tmpn, ea, ean)
          ean = tmpn
        end
        if c != 0; ea[ean] = c; ean += 1; end
      end

      # Add 4*a2
      if a2n > 0
        top = limbs_lshift(tmp, a2, a2n, 2)
        tmpn = a2n
        if top != 0; tmp[tmpn] = top; tmpn += 1; end
        if ean >= tmpn
          c = limbs_add(ea, ea, ean, tmp, tmpn)
        else
          c = limbs_add(ea, tmp, tmpn, ea, ean)
          ean = tmpn
        end
        if c != 0; ea[ean] = c; ean += 1; end
      end

      while ean > 1 && ea[ean - 1] == 0; ean -= 1; end
      ean = 1 if ean == 0
      ean
    end

    # Recursive multiply helper for Toom-3 evaluation products.
    # Ensures `an >= bn` then dispatches to the appropriate algorithm.
    protected def self.toom3_mul_recurse(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32, scratch : Pointer(Limb))
      # Ensure an >= bn
      if an < bn
        ap, bp = bp, ap
        an, bn = bn, an
      end
      return if bn == 0 || an == 0
      if bn < KARATSUBA_THRESHOLD
        limbs_mul_schoolbook(rp, ap, an, bp, bn)
      elsif bn < TOOM3_THRESHOLD
        limbs_mul_karatsuba(rp, ap, an, bp, bn, scratch)
      else
        limbs_mul_toom3(rp, ap, an, bp, bn, scratch)
      end
    end

    # Toom-3 interpolation. Recovers coefficients c0..c4 and writes the final product to rp.
    #
    # Formulas (derived from inverting the 5-point evaluation matrix):
    #   c0 = w0
    #   c4 = winf
    #   c2 = (w1 + wm1)/2 - c0 - c4
    #   t  = (w1 - wm1)/2                  (= c1 + c3)
    #   c3 = ((w2 - w0)/2 - t - 2*c2 - 8*c4) / 3
    #   c1 = t - c3
    #
    # Result = c0 + c1*B^k + c2*B^(2k) + c3*B^(3k) + c4*B^(4k).
    protected def self.toom3_interpolate(rp : Pointer(Limb), rn : Int32,
                                          k : Int32,
                                          w0 : Pointer(Limb), w0n : Int32,
                                          w1 : Pointer(Limb), w1n : Int32,
                                          wm1 : Pointer(Limb), wm1n : Int32, wm1_neg : Bool,
                                          w2 : Pointer(Limb), w2n : Int32,
                                          winf : Pointer(Limb), winfn : Int32,
                                          c2 : Pointer(Limb), t : Pointer(Limb), tmp8 : Pointer(Limb))
      # c2, t, tmp8 are pre-allocated from scratch (each at least 2*k+4 limbs).
      maxn = 2 * k + 4

      # --- c2 = (w1 + wm1) / 2 - w0 - winf ---
      # w1 + signed_wm1: if wm1_neg, w1 + (-|wm1|) = w1 - |wm1|; else w1 + |wm1|
      # w1 + wm1 = 2*(c0 + c2 + c4), always non-negative.
      if wm1_neg
        c2n = w1n
        w1n.times { |i| c2[i] = w1[i] }
        limbs_sub(c2, c2, c2n, wm1, wm1n) if wm1n > 0
      else
        if w1n >= wm1n
          c = limbs_add(c2, w1, w1n, wm1, wm1n)
          c2n = w1n
        else
          c = limbs_add(c2, wm1, wm1n, w1, w1n)
          c2n = wm1n
        end
        if c != 0; c2[c2n] = c; c2n += 1; end
      end
      while c2n > 1 && c2[c2n - 1] == 0; c2n -= 1; end
      limbs_rshift(c2, c2, c2n, 1) if c2n > 0
      # Subtract w0
      if w0n > 0
        c2n = Math.max(c2n, w0n) if w0n > c2n
        limbs_sub(c2, c2, c2n, w0, w0n)
      end
      # Subtract winf
      if winfn > 0
        c2n = Math.max(c2n, winfn) if winfn > c2n
        limbs_sub(c2, c2, c2n, winf, winfn)
      end
      while c2n > 1 && c2[c2n - 1] == 0; c2n -= 1; end

      # --- t = (w1 - wm1) / 2 = c1 + c3 (always non-negative) ---
      if wm1_neg
        # w1 - (-|wm1|) = w1 + |wm1|
        if w1n >= wm1n
          c = limbs_add(t, w1, w1n, wm1, wm1n)
          tn = w1n
        else
          c = limbs_add(t, wm1, wm1n, w1, w1n)
          tn = wm1n
        end
        if c != 0; t[tn] = c; tn += 1; end
      else
        # w1 - |wm1|
        tn = w1n
        w1n.times { |i| t[i] = w1[i] }
        limbs_sub(t, t, tn, wm1, wm1n) if wm1n > 0
      end
      while tn > 1 && t[tn - 1] == 0; tn -= 1; end
      limbs_rshift(t, t, tn, 1)
      while tn > 1 && t[tn - 1] == 0; tn -= 1; end

      # --- c3 = ((w2 - w0) / 2 - t - 2*c2 - 8*winf) / 3 ---
      # Compute into w2 buffer (safe to overwrite now).
      # IMPORTANT: Do not trim c3n between operations. Aggressive trimming can make
      # c3n < subtrahend size, causing limbs_sub to read beyond valid data.
      c3 = w2
      c3n = w2n
      # c3 = w2 - w0
      limbs_sub(c3, c3, c3n, w0, w0n) if w0n > 0 && c3n >= w0n
      # c3 = c3 / 2
      limbs_rshift(c3, c3, c3n, 1) if c3n > 0
      # c3 -= t
      if tn > 0
        c3n = Math.max(c3n, tn) if tn > c3n
        limbs_sub(c3, c3, c3n, t, tn)
      end
      # c3 -= 2*c2
      if c2n > 0
        c3n = Math.max(c3n, c2n) if c2n > c3n
        limbs_sub(c3, c3, c3n, c2, c2n)
        limbs_sub(c3, c3, c3n, c2, c2n)
      end
      # c3 -= 8*winf
      if winfn > 0
        top = limbs_lshift(tmp8, winf, winfn, 3)
        tmp8n = winfn
        if top != 0; tmp8[tmp8n] = top; tmp8n += 1; end
        c3n = Math.max(c3n, tmp8n) if tmp8n > c3n
        limbs_sub(c3, c3, c3n, tmp8, tmp8n)
      end
      # Trim before dividing by 3
      while c3n > 1 && c3[c3n - 1] == 0; c3n -= 1; end
      # c3 /= 3
      limbs_div_rem_1(c3, c3, c3n, 3_u64)
      while c3n > 1 && c3[c3n - 1] == 0; c3n -= 1; end

      # --- c1 = t - c3 ---
      c1 = t  # reuse t buffer (t = c1 + c3, so c1 = t - c3)
      c1n = tn
      if c3n > 0
        c1n = Math.max(c1n, c3n) if c3n > c1n
        limbs_sub(c1, c1, c1n, c3, c3n)
      end
      while c1n > 1 && c1[c1n - 1] == 0; c1n -= 1; end

      # --- Recompose: result = c0 + c1*B^k + c2*B^(2k) + c3*B^(3k) + c4*B^(4k) ---
      rn.times { |i| rp[i] = 0_u64 }

      # c0 = w0 at offset 0
      w0n.times { |i| rp[i] = w0[i] } if w0n > 0

      # c4 = winf at offset 4k
      winfn.times { |i| rp[4 * k + i] = winf[i] } if winfn > 0

      # c1 at offset k (add)
      limbs_add(rp + k, rp + k, rn - k, c1, c1n) if c1n > 0

      # c2 at offset 2k (add)
      limbs_add(rp + 2 * k, rp + 2 * k, rn - 2 * k, c2, c2n) if c2n > 0

      # c3 at offset 3k (add)
      limbs_add(rp + 3 * k, rp + 3 * k, rn - 3 * k, c3, c3n) if c3n > 0
    end

    # --- NTT-based multiplication for very large numbers (>= 25,000 limbs) ---
    # Uses Number Theoretic Transform with the Goldilocks prime p = 2^64 - 2^32 + 1.
    # Each 64-bit limb is split into two 32-bit halves so convolution coefficients
    # stay below `n * (2^32 - 1)^2 < p` for `n < 2^32` (billions of limbs).
    # This avoids multi-prime CRT and enables fast Goldilocks modular reduction
    # (no 128-bit division). Achieves O(n log n) multiplication.

    # Goldilocks prime: p = 2^64 - 2^32 + 1.
    NTT_P = 0xFFFFFFFF00000001_u64
    # Primitive root mod `NTT_P`.
    NTT_G = 7_u64

    # Goldilocks modular reduction: computes `(a * b) mod p` without 128-bit division.
    # Exploits `2^64 = 2^32 - 1 (mod p)` for fast reduction via shifts and subtracts.
    @[AlwaysInline]
    private def self.goldilocks_mulmod(a : UInt64, b : UInt64) : UInt64
      prod = a.to_u128 &* b.to_u128
      lo = prod.to_u64!
      hi = (prod >> 64).to_u64!
      # lo + hi * (2^32 - 1) = lo + hi * 2^32 - hi
      # = lo - hi + hi * 2^32
      # Split hi*2^32: upper 32 bits go to next reduction
      hi_lo = hi & 0xFFFFFFFF_u64          # low 32 bits of hi
      hi_hi = hi >> 32                      # high 32 bits of hi
      # result = lo + hi_lo * 2^32 - hi + hi_hi * (2^32-1)  [from reducing hi_hi * 2^64]
      # But we can accumulate more carefully:
      # step 1: t = lo - hi (mod p)
      # step 2: t += (hi << 32) (mod p)  — but hi<<32 might overflow u64
      # Use a different decomposition:
      # result = lo + hi * 2^32 - hi  (mod p)
      # hi * 2^32 = (hi_hi << 64) | (hi_lo << 32)
      # So: result = lo + (hi_lo << 32) - hi + hi_hi * (2^32 - 1)  (mod p)
      #            = lo + (hi_lo << 32) - hi + (hi_hi << 32) - hi_hi  (mod p)
      #            = lo + ((hi_lo + hi_hi) << 32) - hi - hi_hi  (mod p)
      # This is getting complex. Use a simpler 2-step reduction:
      p = NTT_P
      # Step 1: reduce hi*2^64 → hi*(2^32-1)
      t1 = (hi.to_u128 << 32) &- hi.to_u128  # hi * (2^32 - 1), fits in ~96 bits
      s = lo.to_u128 &+ t1
      # Step 2: if s >= 2^64, reduce again
      lo2 = s.to_u64!
      hi2 = (s >> 64).to_u64!
      if hi2 > 0
        t2 = (hi2.to_u128 << 32) &- hi2.to_u128
        s2 = lo2.to_u128 &+ t2
        lo2 = s2.to_u64!
        hi2 = (s2 >> 64).to_u64!
        if hi2 > 0
          # One more reduction (rare)
          t3 = (hi2.to_u128 << 32) &- hi2.to_u128
          lo2 = (lo2.to_u128 &+ t3).to_u64!
        end
      end
      # Final canonical reduction
      lo2 >= p ? lo2 &- p : lo2
    end

    # Modular exponentiation mod Goldilocks prime using square-and-multiply.
    private def self.goldilocks_powmod(base : UInt64, exp : UInt64) : UInt64
      result = 1_u64
      b = base % NTT_P
      e = exp
      while e > 0
        result = goldilocks_mulmod(result, b) if e & 1 == 1
        e >>= 1
        b = goldilocks_mulmod(b, b) if e > 0
      end
      result
    end

    # In-place iterative Cooley-Tukey NTT (forward transform) using Goldilocks prime.
    # Performs bit-reversal permutation then log2(n) butterfly stages.
    private def self.ntt_forward(data : Pointer(UInt64), n : Int32, g : UInt64)
      p = NTT_P
      # Bit-reversal permutation
      j = 0
      i = 1
      while i < n
        bit = n >> 1
        while j & bit != 0
          j ^= bit
          bit >>= 1
        end
        j ^= bit
        if i < j
          data[i], data[j] = data[j], data[i]
        end
        i += 1
      end

      # Butterfly stages
      len = 2
      while len <= n
        w = goldilocks_powmod(g, (p - 1) // len.to_u64!)
        half = len >> 1
        i = 0
        while i < n
          wn = 1_u64
          k = 0
          while k < half
            u = data[i + k]
            v = goldilocks_mulmod(data[i + k + half], wn)
            sum = u &+ v
            data[i + k] = sum >= p ? sum &- p : sum
            data[i + k + half] = u >= v ? u &- v : u &+ p &- v
            wn = goldilocks_mulmod(wn, w)
            k += 1
          end
          i += len
        end
        len <<= 1
      end
    end

    # Inverse NTT: forward transform with inverse root, then multiply by `n^-1 mod p`.
    private def self.ntt_inverse(data : Pointer(UInt64), n : Int32, g : UInt64)
      g_inv = goldilocks_powmod(g, NTT_P - 2)
      ntt_forward(data, n, g_inv)
      n_inv = goldilocks_powmod(n.to_u64!, NTT_P - 2)
      i = 0
      while i < n
        data[i] = goldilocks_mulmod(data[i], n_inv)
        i += 1
      end
    end

    # NTT-based multiplication for large limb arrays (>= `NTT_THRESHOLD` limbs).
    # Splits each 64-bit limb into two 32-bit halves, performs cyclic convolution
    # using forward NTT, pointwise multiply, and inverse NTT, then reconstructs
    # 64-bit limbs with carry propagation. O(n log n) time complexity.
    protected def self.limbs_mul_ntt(rp : Pointer(Limb), ap : Pointer(Limb), an : Int32, bp : Pointer(Limb), bn : Int32)
      # Split into 32-bit pieces: 2*an and 2*bn elements
      sa = an * 2
      sb = bn * 2
      result_pieces = sa + sb  # convolution output length

      # Transform size: next power of 2 >= result_pieces
      n = 1
      while n < result_pieces
        n <<= 1
      end

      # Split and zero-pad
      fa = Pointer(UInt64).malloc(n)
      fb = Pointer(UInt64).malloc(n)
      i = 0
      while i < an
        fa[i * 2] = ap[i] & 0xFFFFFFFF_u64
        fa[i * 2 + 1] = ap[i] >> 32
        i += 1
      end
      i = 0
      while i < bn
        fb[i * 2] = bp[i] & 0xFFFFFFFF_u64
        fb[i * 2 + 1] = bp[i] >> 32
        i += 1
      end

      ntt_forward(fa, n, NTT_G)
      ntt_forward(fb, n, NTT_G)

      # Pointwise multiply
      i = 0
      while i < n
        fa[i] = goldilocks_mulmod(fa[i], fb[i])
        i += 1
      end

      ntt_inverse(fa, n, NTT_G)

      # Reconstruct 64-bit limbs from 32-bit convolution results with carry propagation.
      # Each fa[k] is the sum of products of 32-bit pieces.
      # Pairs of consecutive pieces combine into one 64-bit limb.
      result_len = an + bn
      carry = 0_u128
      i = 0
      while i < result_len
        lo_idx = i * 2
        hi_idx = i * 2 + 1
        lo_val = lo_idx < result_pieces ? fa[lo_idx].to_u128 : 0_u128
        hi_val = hi_idx < result_pieces ? fa[hi_idx].to_u128 : 0_u128
        total = lo_val &+ (hi_val << 32) &+ carry
        rp[i] = total.to_u64!
        carry = total >> 64
        i += 1
      end
    end

    # Divides a limb array by a single limb. Stores quotient in `qp` (may alias `ap`).
    # Returns the remainder. Uses 128-bit division for each limb pair.
    protected def self.limbs_div_rem_1(qp : Pointer(Limb), ap : Pointer(Limb), n : Int32, d : Limb) : Limb
      raise DivisionByZeroError.new if d == 0
      rem = 0_u128
      i = n - 1
      while i >= 0
        cur = (rem << 64) | ap[i].to_u128
        qp[i] = (cur // d.to_u128).to_u64!
        rem = cur % d.to_u128
        i -= 1
      end
      rem.to_u64!
    end

    # Left-shifts a limb array by *shift* bits (0 < shift < 64).
    # Returns the bits shifted out of the top limb.
    protected def self.limbs_lshift(rp : Pointer(Limb), ap : Pointer(Limb), n : Int32, shift : Int32) : Limb
      return 0_u64 if shift == 0
      complement = 64 - shift
      carry = 0_u64
      i = 0
      while i < n
        new_carry = ap[i] >> complement
        rp[i] = (ap[i] << shift) | carry
        carry = new_carry
        i += 1
      end
      carry
    end

    # Right-shifts a limb array by *shift* bits (0 < shift < 64).
    # Returns the bits shifted out of the bottom limb.
    protected def self.limbs_rshift(rp : Pointer(Limb), ap : Pointer(Limb), n : Int32, shift : Int32) : Limb
      return 0_u64 if shift == 0
      complement = 64 - shift
      carry = 0_u64
      i = n - 1
      while i >= 0
        new_carry = ap[i] << complement
        rp[i] = (ap[i] >> shift) | carry
        carry = new_carry
        i -= 1
      end
      carry
    end

    # Knuth Algorithm D (TAOCP 4.3.1): multi-limb division.
    # Divides `np[0..nn-1]` by `dp[0..dn-1]`, storing quotient in `qp` and
    # remainder in `rp`. Normalizes the divisor so its top limb has its high
    # bit set, estimates each quotient digit with a 2-by-1 trial division,
    # refines the estimate, and applies add-back correction when needed.
    # Requires `nn >= dn >= 2` and `dp[dn-1] != 0`.
    protected def self.limbs_div_rem(qp : Pointer(Limb), rp : Pointer(Limb),
                                     np : Pointer(Limb), nn : Int32,
                                     dp : Pointer(Limb), dn : Int32,
                                     scratch : Pointer(Limb))
      # Step D1: Normalize — shift so that dp[dn-1] has its high bit set.
      shift = dp[dn - 1].leading_zeros_count.to_i32
      # Use scratch for working copies: un at scratch[0..nn], vn at scratch[nn+1..nn+dn]
      un = scratch                  # normalized dividend (nn+1 limbs)
      vn = scratch + (nn + 1)       # normalized divisor (dn limbs)

      if shift > 0
        limbs_lshift(vn, dp, dn, shift)
        un[nn] = limbs_lshift(un, np, nn, shift)
      else
        un.copy_from(np, nn)
        un[nn] = 0_u64
        vn.copy_from(dp, dn)
      end

      qn = nn - dn + 1 # number of quotient limbs

      j = qn - 1
      while j >= 0
        # Step D3: Calculate q_hat — estimate quotient digit.
        # q_hat = (un[j+dn]*B + un[j+dn-1]) / vn[dn-1], clamped to B-1.
        u_hi = un[j + dn].to_u128
        u_lo = un[j + dn - 1].to_u128
        v_top = vn[dn - 1].to_u128

        dividend_top = (u_hi << 64) | u_lo
        q_hat = dividend_top // v_top
        r_hat = dividend_top % v_top

        # Refine: while q_hat >= B or q_hat * vn[dn-2] > B*r_hat + un[j+dn-2]
        base = 1_u128 << 64
        while q_hat >= base || q_hat * vn[dn - 2].to_u128 > (r_hat << 64) + un[j + dn - 2].to_u128
          q_hat -= 1
          r_hat += v_top
          break if r_hat >= base
        end

        # Step D4: Multiply and subtract: un[j..j+dn] -= q_hat * vn[0..dn-1]
        borrow = limbs_submul_1(un + j, vn, dn, q_hat.to_u64!)
        # Check the top limb
        if un[j + dn] < borrow
          # Step D6: Add back — q_hat was one too large
          q_hat -= 1
          carry = limbs_add(un + j, un + j, dn, vn, dn)
          un[j + dn] = un[j + dn] &+ carry
        end
        un[j + dn] = un[j + dn] &- borrow

        qp[j] = q_hat.to_u64!
        j -= 1
      end

      # Step D8: Unnormalize remainder
      if shift > 0
        limbs_rshift(rp, un, dn, shift)
      else
        rp.copy_from(un, dn)
      end
    end

    # Limb count threshold: Knuth Algorithm D -> Burnikel-Ziegler division.
    BZ_THRESHOLD = 80

    # Burnikel-Ziegler division entry point for divisors >= `BZ_THRESHOLD` limbs.
    # Allocates a `LimbArena` bump allocator upfront to avoid per-recursion malloc,
    # then delegates to the recursive inner implementation.
    protected def self.limbs_div_rem_bz(qp : Pointer(Limb), rp : Pointer(Limb),
                                         np : Pointer(Limb), nn : Int32,
                                         dp : Pointer(Limb), dn : Int32)
      # Estimate arena size: ~6n per recursion level, O(log n) depth
      depth = 0
      t = dn
      while t >= 60
        t = (t + 1) >> 1
        depth += 1
      end
      arena_size = (6 * nn + 4 * dn) * (depth + 2) + nn + dn + 10
      arena = LimbArena.new(arena_size)
      limbs_div_rem_bz_inner(qp, rp, np, nn, dp, dn, arena)
    end

    # Recursive Burnikel-Ziegler division. For `nn <= 2*dn`, performs a single
    # 2n-by-n division. For larger dividends, processes in blocks from most
    # significant to least significant.
    protected def self.limbs_div_rem_bz_inner(qp : Pointer(Limb), rp : Pointer(Limb),
                                                np : Pointer(Limb), nn : Int32,
                                                dp : Pointer(Limb), dn : Int32,
                                                arena : LimbArena)
      # For nn <= 2*dn, single div_2n_by_n (with padding)
      if nn <= 2 * dn
        ap = arena.alloc(2 * dn)
        ap.copy_from(np, nn)
        q_tmp = arena.alloc(dn)
        bz_div_2n_by_n(q_tmp, rp, ap, dp, dn, arena)
        qn = nn - dn + 1
        qp.copy_from(q_tmp, qn)
        return
      end

      # nn > 2*dn: process in blocks from most significant to least significant.
      block = dn
      qn = nn - dn + 1
      blocks = (qn + block - 1) // block

      rem = arena.alloc(nn + 1)
      rem.copy_from(np, nn)
      rem_n = nn

      j = blocks - 1
      while j >= 0
        q_pos = j * block
        above = rem_n - q_pos
        above = 2 * block if above > 2 * block

        if above <= 0
          k = 0
          while k < block && q_pos + k < qn
            qp[q_pos + k] = 0_u64
            k += 1
          end
          j -= 1
          next
        end

        ap = arena.alloc(2 * block)
        ap.copy_from(rem + q_pos, above)

        q_block = arena.alloc(block)
        r_block = arena.alloc(block)
        bz_div_2n_by_n(q_block, r_block, ap, dp, block, arena)

        k = 0
        while k < block && q_pos + k < qn
          qp[q_pos + k] = q_block[k]
          k += 1
        end

        k = 0
        while k < block
          rem[q_pos + k] = r_block[k]
          k += 1
        end
        k = block
        while k < above
          rem[q_pos + k] = 0_u64
          k += 1
        end

        j -= 1
      end

      rp.copy_from(rem, dn)
    end

    # Core Burnikel-Ziegler primitive: divides `A[0..2n-1]` by `B[0..n-1]`.
    # Splits the dividend into two halves and performs two 3n-by-2n divisions.
    # Falls back to Knuth Algorithm D for `n < 60`.
    protected def self.bz_div_2n_by_n(qp : Pointer(Limb), rp : Pointer(Limb),
                                       ap : Pointer(Limb), bp : Pointer(Limb), n : Int32,
                                       arena : LimbArena)
      if n < 60
        scratch = arena.alloc(3 * n + 2)
        limbs_div_rem(qp, rp, ap, 2 * n, bp, n, scratch)
        return
      end

      k = (n + 1) >> 1 # ceil(n/2)

      a_hi = arena.alloc(n + k)
      a_hi_actual = 2 * n - k
      a_hi.copy_from(ap + k, a_hi_actual)

      r1 = arena.alloc(n + 1)
      bz_div_3n_by_2n(qp + k, r1, a_hi, bp, n, k, arena)

      a_lo = arena.alloc(n + k)
      a_lo.copy_from(ap, k)
      (a_lo + k).copy_from(r1, n)

      bz_div_3n_by_2n(qp, rp, a_lo, bp, n, k, arena)
    end

    # Burnikel-Ziegler 3n-by-2n division: divides `A[0..n+k-1]` by `B[0..n-1]`
    # where `k = ceil(n/2)`. Computes trial quotient by dividing the top portion
    # by `B`'s upper half, then corrects with add-back if needed.
    protected def self.bz_div_3n_by_2n(qp : Pointer(Limb), rp : Pointer(Limb),
                                        ap : Pointer(Limb), bp : Pointer(Limb),
                                        n : Int32, k : Int32, arena : LimbArena)
      b1n = n - k

      a_top = ap + k
      b1 = bp + k

      if b1n == 0
        qp.copy_from(a_top, k)
        rp.copy_from(ap, n)
        return
      end

      q_hat_cap = k + 1
      q_hat = arena.alloc(q_hat_cap)
      r1 = arena.alloc(b1n + 1)

      if b1n < 60
        scratch = arena.alloc(n + b1n + 2)
        limbs_div_rem(q_hat, r1, a_top, n, b1, b1n, scratch)
      else
        limbs_div_rem_bz_inner(q_hat, r1, a_top, n, b1, b1n, arena)
      end

      q_hat_n = q_hat_cap
      while q_hat_n > 0 && q_hat[q_hat_n - 1] == 0
        q_hat_n -= 1
      end

      b0 = bp
      d = arena.alloc(q_hat_n + k + 1)
      d_n = 0
      if q_hat_n > 0 && k > 0
        if q_hat_n >= k
          limbs_mul(d, q_hat, q_hat_n, b0, k)
        else
          limbs_mul(d, b0, k, q_hat, q_hat_n)
        end
        d_n = q_hat_n + k
        while d_n > 0 && d[d_n - 1] == 0
          d_n -= 1
        end
      end

      rp.copy_from(ap, k)
      i = 0
      while i < b1n && k + i < n
        rp[k + i] = r1[i]
        i += 1
      end
      while k + i < n
        rp[k + i] = 0_u64
        i += 1
      end

      if d_n > 0
        if d_n <= n
          borrow = limbs_sub(rp, rp, n, d, d_n)
        else
          borrow = 1_u64
        end

        while borrow > 0
          if q_hat_n > 0
            i = 0
            b = 1_u64
            while i < q_hat_n && b > 0
              old = q_hat[i]
              q_hat[i] = old &- b
              b = old < b ? 1_u64 : 0_u64
              i += 1
            end
          end
          carry = limbs_add(rp, rp, n, bp, n)
          borrow = borrow > carry ? borrow - carry : 0_u64
        end
      end

      q_hat_n = q_hat_cap
      while q_hat_n > 0 && q_hat[q_hat_n - 1] == 0
        q_hat_n -= 1
      end

      i = 0
      while i < k
        qp[i] = i < q_hat_n ? q_hat[i] : 0_u64
        i += 1
      end
    end

    # Returns `{chunk_size, base^chunk_size}` for chunked string parsing/conversion.
    # `chunk_size` is the largest *k* such that `base^k` fits in a `UInt64`.
    # Common bases (2, 8, 10, 16) use precomputed values.
    protected def self.chunk_params(base : Int32) : {Int32, UInt64}
      # Precomputed for common bases
      case base
      when 2  then {63, 1_u64 << 63}
      when 8  then {21, 8_u64 ** 21}
      when 10 then {19, 10_u64 ** 19}
      when 16 then {15, 1_u64 << 60}
      else
        # Compute: largest k where base^k < 2^64
        k = 1
        power = base.to_u64
        while power <= UInt64::MAX // base.to_u64
          k += 1
          power = power &* base.to_u64
        end
        {k, power}
      end
    end

    # Converts a character to its digit value in the given base. Raises for invalid digits.
    protected def self.char_to_digit(c : Char, base : Int32) : Int32
      d = case c
          when '0'..'9' then c.ord - '0'.ord
          when 'a'..'z' then c.ord - 'a'.ord + 10
          when 'A'..'Z' then c.ord - 'A'.ord + 10
          else               raise ArgumentError.new("Invalid digit '#{c}' for base #{base}")
          end
      raise ArgumentError.new("Digit '#{c}' out of range for base #{base}") if d >= base
      d
    end

    # Converts a digit value (0-35) to its character representation ('0'-'9', 'a'-'z').
    protected def self.digit_to_char(d : UInt8) : Char
      if d < 10
        ('0'.ord + d).chr
      else
        ('a'.ord + d - 10).chr
      end
    end
  end
end
