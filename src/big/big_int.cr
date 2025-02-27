require "c/string"
require "big"
require "random"

# A `BigInt` can represent arbitrarily large integers.
#
# It is implemented under the hood with [GMP](https://gmplib.org/).
struct BigInt < Int
  include Comparable(Int::Signed)
  include Comparable(Int::Unsigned)
  include Comparable(BigInt)
  include Comparable(Float)

  # Creates a `BigInt` with the value zero.
  #
  # ```
  # require "big"
  #
  # BigInt.new # => 0
  # ```
  def initialize
    LibGMP.init(out @mpz)
  end

  # Creates a `BigInt` with the value denoted by *str* in the given *base*.
  #
  # Raises `ArgumentError` if the string doesn't denote a valid integer.
  #
  # ```
  # require "big"
  #
  # BigInt.new("123456789123456789123456789123456789") # => 123456789123456789123456789123456789
  # BigInt.new("123_456_789_123_456_789_123_456_789")  # => 123456789123456789123456789
  # BigInt.new("1234567890ABCDEF", base: 16)           # => 1311768467294899695
  # ```
  def initialize(str : String, base = 10)
    # Strip leading '+' char to smooth out cases with strings like "+123"
    str = str.lchop('+')
    # Strip '_' to make it compatible with int literals like "1_000_000"
    str = str.delete('_')
    err = LibGMP.init_set_str(out @mpz, str, base)
    if err == -1
      raise ArgumentError.new("Invalid BigInt: #{str}")
    end
  end

  # Creates a `BigInt` from the given *num*.
  def initialize(num : Int::Signed)
    if LibC::Long::MIN <= num <= LibC::Long::MAX
      LibGMP.init_set_si(out @mpz, num)
    else
      LibGMP.init_set_str(out @mpz, num.to_s, 10)
    end
  end

  # :ditto:
  def initialize(num : Int::Unsigned)
    if num <= LibC::ULong::MAX
      LibGMP.init_set_ui(out @mpz, num)
    else
      LibGMP.init_set_str(out @mpz, num.to_s, 10)
    end
  end

  # :ditto:
  def initialize(num : Float::Primitive)
    LibGMP.init_set_d(out @mpz, num)
  end

  # :ditto:
  def self.new(num : BigFloat)
    num.to_big_i
  end

  # :ditto:
  def self.new(num : BigDecimal)
    num.to_big_i
  end

  # :ditto:
  def self.new(num : BigRational)
    num.to_big_i
  end

  # Returns *num*. Useful for generic code that does `T.new(...)` with `T`
  # being a `Number`.
  def self.new(num : BigInt)
    num
  end

  # :nodoc:
  def initialize(@mpz : LibGMP::MPZ)
  end

  # :nodoc:
  def self.new
    LibGMP.init(out mpz)
    yield pointerof(mpz)
    new(mpz)
  end

  def <=>(other : BigInt)
    LibGMP.cmp(mpz, other)
  end

  def <=>(other : Int::Signed)
    if LibC::Long::MIN <= other <= LibC::Long::MAX
      LibGMP.cmp_si(mpz, other)
    else
      self <=> BigInt.new(other)
    end
  end

  def <=>(other : Int::Unsigned)
    if other <= LibC::ULong::MAX
      LibGMP.cmp_ui(mpz, other)
    else
      self <=> BigInt.new(other)
    end
  end

  def <=>(other : Float)
    LibGMP.cmp_d(mpz, other)
  end

  def +(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.add(mpz, self, other) }
  end

  def +(other : Int) : BigInt
    if other < 0
      self - other.abs
    elsif other <= LibGMP::ULong::MAX
      BigInt.new { |mpz| LibGMP.add_ui(mpz, self, other) }
    else
      self + other.to_big_i
    end
  end

  def &+(other) : BigInt
    self + other
  end

  def -(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.sub(mpz, self, other) }
  end

  def -(other : Int) : BigInt
    if other < 0
      self + other.abs
    elsif other <= LibGMP::ULong::MAX
      BigInt.new { |mpz| LibGMP.sub_ui(mpz, self, other) }
    else
      self - other.to_big_i
    end
  end

  def &-(other) : BigInt
    self - other
  end

  def - : BigInt
    BigInt.new { |mpz| LibGMP.neg(mpz, self) }
  end

  def abs : BigInt
    BigInt.new { |mpz| LibGMP.abs(mpz, self) }
  end

  def factorial : BigInt
    if self < 0
      raise ArgumentError.new("Factorial not defined for negative values")
    elsif self > LibGMP::ULong::MAX
      raise ArgumentError.new("Factorial not supported for numbers bigger than 2^64")
    end
    BigInt.new { |mpz| LibGMP.fac_ui(mpz, self) }
  end

  def *(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.mul(mpz, self, other) }
  end

  def *(other : LibGMP::IntPrimitiveSigned) : BigInt
    BigInt.new { |mpz| LibGMP.mul_si(mpz, self, other) }
  end

  def *(other : LibGMP::IntPrimitiveUnsigned) : BigInt
    BigInt.new { |mpz| LibGMP.mul_ui(mpz, self, other) }
  end

  def *(other : Int) : BigInt
    self * other.to_big_i
  end

  def &*(other) : BigInt
    self * other
  end

  Number.expand_div [BigInt], BigFloat
  Number.expand_div [BigDecimal], BigDecimal
  Number.expand_div [BigRational], BigRational

  def //(other : Int::Unsigned) : BigInt
    check_division_by_zero other
    unsafe_floored_div(other)
  end

  def //(other : Int) : BigInt
    check_division_by_zero other

    if other < 0
      (-self).unsafe_floored_div(-other)
    else
      unsafe_floored_div(other)
    end
  end

  def tdiv(other : Int) : BigInt
    check_division_by_zero other

    unsafe_truncated_div(other)
  end

  def unsafe_floored_div(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.fdiv_q(mpz, self, other) }
  end

  def unsafe_floored_div(other : Int) : BigInt
    if LibGMP::ULong == UInt32 && (other < Int32::MIN || other > UInt32::MAX)
      unsafe_floored_div(other.to_big_i)
    elsif other < 0
      -BigInt.new { |mpz| LibGMP.fdiv_q_ui(mpz, self, other.abs) }
    else
      BigInt.new { |mpz| LibGMP.fdiv_q_ui(mpz, self, other) }
    end
  end

  def unsafe_truncated_div(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.tdiv_q(mpz, self, other) }
  end

  def unsafe_truncated_div(other : Int) : BigInt
    if LibGMP::ULong == UInt32 && (other < Int32::MIN || other > UInt32::MAX)
      unsafe_truncated_div(other.to_big_i)
    elsif other < 0
      -BigInt.new { |mpz| LibGMP.tdiv_q_ui(mpz, self, other.abs) }
    else
      BigInt.new { |mpz| LibGMP.tdiv_q_ui(mpz, self, other) }
    end
  end

  def %(other : Int) : BigInt
    check_division_by_zero other

    if other < 0
      -(-self).unsafe_floored_mod(-other)
    else
      unsafe_floored_mod(other)
    end
  end

  def remainder(other : Int) : BigInt
    check_division_by_zero other

    unsafe_truncated_mod(other)
  end

  def divmod(number : BigInt) : {BigInt, BigInt}
    check_division_by_zero number

    unsafe_floored_divmod(number)
  end

  def divmod(number : LibGMP::ULong)
    check_division_by_zero number
    unsafe_floored_divmod(number)
  end

  def divmod(number : Int::Signed) : {BigInt, BigInt}
    check_division_by_zero number
    if number > 0 && number <= LibC::Long::MAX
      unsafe_floored_divmod(LibGMP::ULong.new(number))
    else
      divmod(number.to_big_i)
    end
  end

  def divmod(number : Int::Unsigned)
    check_division_by_zero number
    if number <= LibC::ULong::MAX
      unsafe_floored_divmod(LibGMP::ULong.new(number))
    else
      divmod(number.to_big_i)
    end
  end

  def unsafe_floored_mod(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.fdiv_r(mpz, self, other) }
  end

  def unsafe_floored_mod(other : Int) : BigInt
    if (other < LibGMP::Long::MIN || other > LibGMP::ULong::MAX)
      unsafe_floored_mod(other.to_big_i)
    elsif other < 0
      -BigInt.new { |mpz| LibGMP.fdiv_r_ui(mpz, self, other.abs) }
    else
      BigInt.new { |mpz| LibGMP.fdiv_r_ui(mpz, self, other) }
    end
  end

  def unsafe_truncated_mod(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.tdiv_r(mpz, self, other) }
  end

  def unsafe_truncated_mod(other : LibGMP::IntPrimitive) : BigInt
    BigInt.new { |mpz| LibGMP.tdiv_r_ui(mpz, self, other.abs) }
  end

  def unsafe_truncated_mod(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.tdiv_r_ui(mpz, self, other.abs.to_big_i) }
  end

  def unsafe_floored_divmod(number : BigInt) : {BigInt, BigInt}
    the_q = BigInt.new
    the_r = BigInt.new { |r| LibGMP.fdiv_qr(the_q, r, self, number) }
    {the_q, the_r}
  end

  def unsafe_floored_divmod(number : LibGMP::ULong) : {BigInt, BigInt}
    the_q = BigInt.new
    the_r = BigInt.new { |r| LibGMP.fdiv_qr_ui(the_q, r, self, number) }
    {the_q, the_r}
  end

  def unsafe_truncated_divmod(number : BigInt)
    the_q = BigInt.new
    the_r = BigInt.new { |r| LibGMP.tdiv_qr(the_q, r, self, number) }
    {the_q, the_r}
  end

  def unsafe_truncated_divmod(number : LibGMP::ULong)
    the_q = BigInt.new
    the_r = BigInt.new { |r| LibGMP.tdiv_qr_ui(the_q, r, self, number) }
    {the_q, the_r}
  end

  def divisible_by?(number : BigInt) : Bool
    LibGMP.divisible_p(self, number) != 0
  end

  def divisible_by?(number : LibGMP::ULong) : Bool
    LibGMP.divisible_ui_p(self, number) != 0
  end

  def divisible_by?(number : Int) : Bool
    if 0 <= number <= LibGMP::ULong::MAX
      LibGMP.divisible_ui_p(self, number) != 0
    elsif LibGMP::Long::MIN < number < 0
      LibGMP.divisible_ui_p(self, number.abs) != 0
    else
      divisible_by?(number.to_big_i)
    end
  end

  # :nodoc:
  # returns `{reduced, count}` such that `self % (number ** count) == 0`,
  # `self % (number ** (count + 1)) != 0`, and `reduced == self / (number ** count)`
  def factor_by(number : Int) : {BigInt, UInt64}
    return {self, 0_u64} unless divisible_by?(number)

    reduced = BigInt.new
    count = LibGMP.remove(reduced, self, number.to_big_i)
    {reduced, count.to_u64}
  end

  def ~ : BigInt
    BigInt.new { |mpz| LibGMP.com(mpz, self) }
  end

  def &(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.and(mpz, self, other.to_big_i) }
  end

  def |(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.ior(mpz, self, other.to_big_i) }
  end

  def ^(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.xor(mpz, self, other.to_big_i) }
  end

  def >>(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.fdiv_q_2exp(mpz, self, other) }
  end

  # :nodoc:
  #
  # Because every Int needs this method.
  def unsafe_shr(count : Int) : self
    self >> count
  end

  def <<(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.mul_2exp(mpz, self, other) }
  end

  def **(other : Int) : BigInt
    if other < 0
      raise ArgumentError.new("Negative exponent isn't supported")
    end
    BigInt.new { |mpz| LibGMP.pow_ui(mpz, self, other) }
  end

  # Returns the greatest common divisor of `self` and *other*.
  def gcd(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.gcd(mpz, self, other) }
  end

  # :ditto:
  def gcd(other : Int) : Int
    result = LibGMP.gcd_ui(nil, self, other.abs.to_u64)
    result == 0 ? self : result
  end

  # Returns the least common multiple of `self` and *other*.
  def lcm(other : BigInt) : BigInt
    BigInt.new { |mpz| LibGMP.lcm(mpz, self, other) }
  end

  # :ditto:
  def lcm(other : Int) : BigInt
    BigInt.new { |mpz| LibGMP.lcm_ui(mpz, self, other.abs.to_u64) }
  end

  def bit_length : Int32
    LibGMP.sizeinbase(self, 2).to_i
  end

  # TODO: check hash equality for numbers >= 2**63
  def_hash to_i64!

  def to_s(base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : String
    raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36 || base == 62
    raise ArgumentError.new("upcase must be false for base 62") if upcase && base == 62
    raise ArgumentError.new("Precision must be non-negative") unless precision >= 0

    case {self, precision}
    when {0, 0}
      ""
    when {0, 1}
      "0"
    when {1, 1}
      "1"
    else
      count = LibGMP.sizeinbase(self, base).to_i
      negative = self < 0

      if precision <= count
        len = count + (negative ? 1 : 0)
        String.new(len + 1) do |buffer| # null terminator required by GMP
          buffer[len - 1] = 0
          LibGMP.get_str(buffer, upcase ? -base : base, self)

          # `sizeinbase` may be 1 greater than the exact value
          if buffer[len - 1] == 0
            if precision == count
              # In this case the exact `count` is `precision - 1`, i.e. one zero
              # should be inserted at the beginning of the number
              # e.g. precision = 3, count = 3, exact count = 2
              # "85\0\0" -> "085\0" for positive
              # "-85\0\0" -> "-085\0" for negative
              start = buffer + (negative ? 1 : 0)
              start.move_to(start + 1, count - 1)
              start.value = '0'.ord.to_u8
            else
              len -= 1
            end
          end

          base62_swapcase(Slice.new(buffer, len)) if base == 62
          {len, len}
        end
      else
        len = precision + (negative ? 1 : 0)
        String.new(len + 1) do |buffer|
          # e.g. precision = 13, count = 8
          # "_____12345678\0" for positive
          # "_____-12345678\0" for negative
          buffer[len - 1] = 0
          start = buffer + precision - count
          LibGMP.get_str(start, upcase ? -base : base, self)

          # `sizeinbase` may be 1 greater than the exact value
          if buffer[len - 1] == 0
            # e.g. precision = 7, count = 3, exact count = 2
            # "____85\0\0" -> "____885\0" for positive
            # "____-85\0\0" -> "____-885\0" for negative
            # `start` will be zero-filled later
            count -= 1
            start += 1 if negative
            start.move_to(start + 1, count)
          end

          base62_swapcase(Slice.new(buffer + len - count, count)) if base == 62

          if negative
            buffer.value = '-'.ord.to_u8
            buffer += 1
          end
          Slice.new(buffer, precision - count).fill('0'.ord.to_u8)

          {len, len}
        end
      end
    end
  end

  def to_s(io : IO, base : Int = 10, *, precision : Int = 1, upcase : Bool = false) : Nil
    raise ArgumentError.new("Invalid base #{base}") unless 2 <= base <= 36 || base == 62
    raise ArgumentError.new("upcase must be false for base 62") if upcase && base == 62
    raise ArgumentError.new("Precision must be non-negative") unless precision >= 0

    case {self, precision}
    when {0, 0}
      # do nothing
    when {0, 1}
      io << '0'
    when {1, 1}
      io << '1'
    else
      count = LibGMP.sizeinbase(self, base).to_i
      ptr = LibGMP.get_str(nil, upcase ? -base : base, self)
      negative = self < 0

      # `sizeinbase` may be 1 greater than the exact value
      count -= 1 if ptr[count + (negative ? 0 : -1)] == 0

      if precision <= count
        buffer = Slice.new(ptr, count + (negative ? 1 : 0))
      else
        if negative
          io << '-'
          ptr += 1 # this becomes the absolute value
        end

        (precision - count).times { io << '0' }
        buffer = Slice.new(ptr, count)
      end

      base62_swapcase(buffer) if base == 62
      io.write_string buffer
    end
  end

  private def base62_swapcase(buffer)
    buffer.map! do |x|
      # for ASCII integers as returned by GMP the only possible characters are
      # '\0', '-', '0'..'9', 'A'..'Z', and 'a'..'z'
      if x & 0x40 != 0 # 'A'..'Z', 'a'..'z'
        x ^ 0x20
      else # '\0', '-', '0'..'9'
        x
      end
    end
  end

  def digits(base = 10) : Array(Int32)
    if self < 0
      raise ArgumentError.new("Can't request digits of negative number")
    end

    ary = [] of Int32
    self.to_s(base).each_char { |c| ary << c.to_i(base) }
    ary.reverse!
    ary
  end

  def popcount : Int
    LibGMP.popcount(self)
  end

  def trailing_zeros_count : Int
    LibGMP.scan1(self, 0)
  end

  def to_i : Int32
    to_i32
  end

  def to_i8 : Int8
    to_i32.to_i8
  end

  def to_i16 : Int16
    to_i32.to_i16
  end

  def to_i32 : Int32
    LibGMP.get_si(self).to_i32
  end

  def to_i64 : Int64
    if LibGMP::Long::MIN <= self <= LibGMP::Long::MAX
      LibGMP.get_si(self).to_i64
    else
      to_s.to_i64 { raise OverflowError.new }
    end
  end

  def to_i!
    to_i32!
  end

  def to_i8! : Int8
    LibGMP.get_si(self).to_i8!
  end

  def to_i16! : Int16
    LibGMP.get_si(self).to_i16!
  end

  def to_i32! : Int32
    LibGMP.get_si(self).to_i32!
  end

  def to_i64! : Int64
    (self % BITS64).to_u64.to_i64!
  end

  def to_u : UInt32
    to_u32
  end

  def to_u8 : UInt8
    to_u32.to_u8
  end

  def to_u16 : UInt16
    to_u32.to_u16
  end

  def to_u32 : UInt32
    to_u64.to_u32
  end

  def to_u64 : UInt64
    if LibGMP::ULong::MIN <= self <= LibGMP::ULong::MAX
      LibGMP.get_ui(self).to_u64
    else
      to_s.to_u64 { raise OverflowError.new }
    end
  end

  def to_u!
    to_u32!
  end

  def to_u8! : UInt8
    LibGMP.get_ui(self).to_u8!
  end

  def to_u16! : UInt16
    LibGMP.get_ui(self).to_u16!
  end

  def to_u32! : UInt32
    LibGMP.get_ui(self).to_u32!
  end

  def to_u64! : UInt64
    (self % BITS64).to_u64
  end

  private BITS64 = BigInt.new(1) << 64

  def to_f : Float64
    to_f64
  end

  def to_f32 : Float32
    to_f64.to_f32
  end

  def to_f64 : Float64
    LibGMP.get_d(self)
  end

  def to_f!
    to_f64!
  end

  def to_f32!
    LibGMP.get_d(self).to_f32!
  end

  def to_f64!
    LibGMP.get_d(self)
  end

  def to_big_i : BigInt
    self
  end

  def to_big_f : BigFloat
    BigFloat.new { |mpf| LibGMP.mpf_set_z(mpf, mpz) }
  end

  def to_big_d : BigDecimal
    BigDecimal.new(self)
  end

  def to_big_r : BigRational
    BigRational.new(self)
  end

  def clone
    self
  end

  private def check_division_by_zero(value)
    if value == 0
      raise DivisionByZeroError.new
    end
  end

  private def mpz
    pointerof(@mpz)
  end

  def to_unsafe
    mpz
  end
end

struct Int
  include Comparable(BigInt)

  def <=>(other : BigInt)
    -(other <=> self)
  end

  def +(other : BigInt) : BigInt
    other + self
  end

  def &+(other : BigInt) : BigInt
    self + other
  end

  def -(other : BigInt) : BigInt
    if self < 0
      -(abs + other)
    else
      # The line below segfault on linux 32 bits for a (yet) unknown reason:
      #
      #     BigInt.new { |mpz| LibGMP.ui_sub(mpz, self.to_u64, other) }
      #
      # So for now we do it a bit slower.
      to_big_i - other
    end
  end

  def &-(other : BigInt) : BigInt
    self - other
  end

  def *(other : BigInt) : BigInt
    other * self
  end

  def &*(other : BigInt) : BigInt
    self * other
  end

  def %(other : BigInt) : BigInt
    to_big_i % other
  end

  # Returns the greatest common divisor of `self` and *other*.
  def gcd(other : BigInt) : Int
    other.gcd(self)
  end

  # Returns the least common multiple of `self` and *other*.
  def lcm(other : BigInt) : BigInt
    other.lcm(self)
  end

  # Returns a `BigInt` representing this integer.
  # ```
  # require "big"
  #
  # 123.to_big_i
  # ```
  def to_big_i : BigInt
    BigInt.new(self)
  end
end

struct Float
  include Comparable(BigInt)

  def <=>(other : BigInt)
    -(other <=> self)
  end

  # Returns a `BigInt` representing this float (rounded using `floor`).
  # ```
  # require "big"
  #
  # 1212341515125412412412421.0.to_big_i
  # ```
  def to_big_i : BigInt
    BigInt.new(self)
  end
end

class String
  # Returns a `BigInt` from this string, in the given *base*.
  #
  # Raises `ArgumentError` if this string doesn't denote a valid integer.
  # ```
  # require "big"
  #
  # "3a060dbf8d1a5ac3e67bc8f18843fc48".to_big_i(16)
  # ```
  def to_big_i(base = 10) : BigInt
    BigInt.new(self, base)
  end
end

module Math
  # Calculates the square root of *value*.
  #
  # ```
  # require "big"
  #
  # Math.sqrt(1_000_000_000_000.to_big_i * 1_000_000_000_000.to_big_i) # => 1000000000000.0
  # ```
  def sqrt(value : BigInt) : BigFloat
    sqrt(value.to_big_f)
  end

  # Calculates the integer square root of *value*.
  def isqrt(value : BigInt)
    BigInt.new { |mpz| LibGMP.sqrt(mpz, value) }
  end
end

module Random
  private def rand_int(max : BigInt) : BigInt
    # This is a copy of the algorithm in random.cr but with fewer special cases.
    unless max > 0
      raise ArgumentError.new "Invalid bound for rand: #{max}"
    end

    rand_max = BigInt.new(1) << (sizeof(typeof(next_u))*8)
    needed_parts = 1
    while rand_max < max && rand_max > 0
      rand_max <<= sizeof(typeof(next_u))*8
      needed_parts += 1
    end

    limit = rand_max // max * max

    loop do
      result = BigInt.new(next_u)
      (needed_parts - 1).times do
        result <<= sizeof(typeof(next_u))*8
        result |= BigInt.new(next_u)
      end

      # For a uniform distribution we may need to throw away some numbers.
      if result < limit
        return result % max
      end
    end
  end

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

# :nodoc:
struct Crystal::Hasher
  private HASH_MODULUS_INT_P = BigInt.new((1_u64 << HASH_BITS) - 1)
  private HASH_MODULUS_INT_N = -BigInt.new((1_u64 << HASH_BITS) - 1)

  def int(value : BigInt)
    # it should calculate `remainder(HASH_MODULUS)`
    if LibGMP::ULong == UInt64
      v = LibGMP.tdiv_ui(value, HASH_MODULUS).to_i64
      value < 0 ? -v : v
    elsif value >= HASH_MODULUS_INT_P || value <= HASH_MODULUS_INT_N
      value.unsafe_truncated_mod(HASH_MODULUS_INT_P).to_i64
    else
      value.to_i64
    end
  end
end
