# :nodoc: Forward declarations
struct BigInt < Int
end

struct BigFloat < Float
end

struct BigRational < Number
end

struct BigDecimal < Number
end

{% if flag?(:use_libgmp) %}
  require "./big/lib_gmp"
  require "./big/big_int"
  require "./big/big_float"
  require "./big/big_rational"
  require "./big/big_decimal"
  require "./big/number"
{% else %}
  require "./big_number"
  require "./big/big_int_pure"
  require "./big/big_float_pure"
  require "./big/big_rational_pure"
  require "./big/big_decimal_pure"
  require "./big/number_pure"
{% end %}
