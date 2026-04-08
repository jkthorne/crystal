require "./big_number/limb"
require "./big_number/big_int"
require "./big_number/big_rational"
require "./big_number/big_float"
require "./big_number/big_decimal"
require "./big_number/ext"

# Pure-Crystal arbitrary-precision arithmetic library with zero C dependencies.
#
# Provides four numeric types:
# - `BigNumber::BigInt` — arbitrary-precision integers (sign-magnitude, 64-bit limbs)
# - `BigNumber::BigRational` — exact rational arithmetic, auto-canonicalized
# - `BigNumber::BigFloat` — arbitrary-precision floating point with configurable precision
# - `BigNumber::BigDecimal` — fixed-scale decimal arithmetic
#
# No FFI, no GMP, no external dependencies. Uses Karatsuba, NTT, Burnikel-Ziegler,
# Montgomery modular exponentiation, and other advanced algorithms for performance.
#
# ```
# require "big_number"
#
# a = BigNumber::BigInt.new("123456789012345678901234567890")
# b = BigNumber::BigInt.new("987654321098765432109876543210")
# puts a * b
# ```
#
# For a drop-in replacement of Crystal's stdlib `BigInt`/`BigFloat`/`BigRational`/`BigDecimal`,
# use `require "big_number/stdlib"` instead.
module BigNumber
  VERSION = "0.1.0"
end
