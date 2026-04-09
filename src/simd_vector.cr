# A fixed-size SIMD vector backed by an LLVM vector type.
#
# `SIMDVector` is a generic type with type argument `T` specifying the element
# type and `N` the number of lanes. For example `SIMDVector(Float32, 4)` is a
# 4-lane vector of `Float32`, mapping to `<4 x float>` in LLVM IR.
#
# Unlike `StaticArray`, which maps to LLVM array types, `SIMDVector` maps to
# LLVM vector types. This means arithmetic operations compile to native SIMD
# instructions (SSE, AVX, NEON, etc.) when the target supports them.
#
# ```
# require "simd_vector"
#
# a = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
# b = SIMDVector[5.0_f32, 6.0_f32, 7.0_f32, 8.0_f32]
# c = a + b # => SIMDVector[6.0, 8.0, 10.0, 12.0]
# ```
#
# The `N` parameter must be a power of 2 (2, 4, 8, 16, 32, or 64).
# The `T` parameter must be a numeric primitive type (`Int8` through `Int64`,
# `UInt8` through `UInt64`, `Float32`, or `Float64`).
#
# NOTE: SIMD support is experimental. The API may change in future releases.
@[Experimental("SIMD support is experimental. The API may change in future releases.")]
struct SIMDVector(T, N)
  # Creates a new `SIMDVector` with the given *args*. The type of the
  # vector will be the union of the type of the given *args*,
  # and its size will be the number of elements.
  #
  # The number of arguments must be a power of 2.
  #
  # ```
  # vec = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
  # vec.unsafe_extract(0) # => 1.0
  # vec.unsafe_extract(3) # => 4.0
  # ```
  macro [](*args)
    %vec = uninitialized ::SIMDVector(typeof({{args.splat}}), {{args.size}})
    {% for arg, i in args %}
      %vec = %vec.unsafe_insert({{i}}, {{arg}})
    {% end %}
    %vec
  end

  # Creates a new `SIMDVector` with all lanes set to the given *value*.
  #
  # ```
  # vec = SIMDVector(Int32, 4).splat(42)
  # vec.unsafe_extract(0) # => 42
  # vec.unsafe_extract(3) # => 42
  # ```
  @[Primitive(:simd_splat)]
  def self.splat(value : T) : self
  end

  # Creates a new `SIMDVector` with all lanes set to zero.
  #
  # ```
  # vec = SIMDVector(Float32, 4).zero
  # vec.unsafe_extract(0) # => 0.0
  # ```
  def self.zero : self
    splat(T.zero)
  end

  # Returns the number of lanes in this vector.
  #
  # ```
  # SIMDVector(Float32, 4).splat(0).size # => 4
  # ```
  def size : Int32
    N
  end

  # Extracts the element at the given *index* without bounds checking.
  #
  # WARNING: Accessing out-of-bounds elements is undefined behavior.
  #
  # ```
  # vec = SIMDVector[10, 20, 30, 40]
  # vec.unsafe_extract(2) # => 30
  # ```
  @[Primitive(:simd_extract)]
  def unsafe_extract(index : Int32) : T
  end

  # Returns a new vector with the element at *index* replaced by *value*,
  # without bounds checking.
  #
  # WARNING: Accessing out-of-bounds elements is undefined behavior.
  #
  # ```
  # vec = SIMDVector[1, 2, 3, 4]
  # vec2 = vec.unsafe_insert(1, 99)
  # vec2.unsafe_extract(1) # => 99
  # ```
  @[Primitive(:simd_insert)]
  def unsafe_insert(index : Int32, value : T) : self
  end

  # Returns the element at the given *index*, with bounds checking.
  #
  # Raises `IndexError` if the index is out of bounds.
  #
  # ```
  # vec = SIMDVector[10, 20, 30, 40]
  # vec[2]  # => 30
  # vec[99] # raises IndexError
  # ```
  def [](index : Int32) : T
    if 0 <= index < N
      unsafe_extract(index)
    else
      raise IndexError.new("SIMDVector index out of bounds: #{index} not in 0...#{N}")
    end
  end

  # --- Elementwise Arithmetic ---

  # Returns a new vector where each lane is the sum of the corresponding
  # lanes in `self` and *other*.
  #
  # ```
  # a = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
  # b = SIMDVector[5.0_f32, 6.0_f32, 7.0_f32, 8.0_f32]
  # c = a + b
  # c[0] # => 6.0
  # ```
  @[Primitive(:simd_binary)]
  def +(other : self) : self
  end

  # Returns a new vector where each lane is the difference of the corresponding
  # lanes in `self` and *other*.
  @[Primitive(:simd_binary)]
  def -(other : self) : self
  end

  # Returns a new vector where each lane is the product of the corresponding
  # lanes in `self` and *other*.
  @[Primitive(:simd_binary)]
  def *(other : self) : self
  end

  # Returns a new vector where each lane is the quotient of the corresponding
  # lanes in `self` and *other*.
  @[Primitive(:simd_binary)]
  def /(other : self) : self
  end

  # Returns a new vector where each lane is the bitwise AND of the corresponding
  # lanes in `self` and *other*. Integer vectors only.
  @[Primitive(:simd_binary)]
  def &(other : self) : self
  end

  # Returns a new vector where each lane is the bitwise OR of the corresponding
  # lanes in `self` and *other*. Integer vectors only.
  @[Primitive(:simd_binary)]
  def |(other : self) : self
  end

  # Returns a new vector where each lane is the bitwise XOR of the corresponding
  # lanes in `self` and *other*. Integer vectors only.
  @[Primitive(:simd_binary)]
  def ^(other : self) : self
  end

  # --- Scalar broadcast arithmetic ---

  # Returns a new vector with *scalar* added to each lane.
  #
  # ```
  # a = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
  # b = a + 10.0_f32
  # b[0] # => 11.0
  # ```
  def +(scalar : T) : self
    self + SIMDVector(T, N).splat(scalar)
  end

  # Returns a new vector with *scalar* subtracted from each lane.
  def -(scalar : T) : self
    self - SIMDVector(T, N).splat(scalar)
  end

  # Returns a new vector with each lane multiplied by *scalar*.
  def *(scalar : T) : self
    self * SIMDVector(T, N).splat(scalar)
  end

  # Returns a new vector with each lane divided by *scalar*.
  def /(scalar : T) : self
    self / SIMDVector(T, N).splat(scalar)
  end

  # --- Elementwise Comparison ---
  # These return a vector of `Bool` (`<N x i1>` in LLVM IR), suitable for
  # use as a selection mask.

  # Returns a vector where each lane is `true` if the corresponding lanes
  # in `self` and *other* are equal.
  @[Primitive(:simd_compare)]
  def cmp_eq(other : self) : SIMDVector(Bool, N)
  end

  # Returns a vector where each lane is `true` if the corresponding lanes
  # in `self` and *other* are not equal.
  @[Primitive(:simd_compare)]
  def cmp_ne(other : self) : SIMDVector(Bool, N)
  end

  # Returns a vector where each lane is `true` if the corresponding lane
  # in `self` is less than the lane in *other*.
  @[Primitive(:simd_compare)]
  def cmp_lt(other : self) : SIMDVector(Bool, N)
  end

  # Returns a vector where each lane is `true` if the corresponding lane
  # in `self` is less than or equal to the lane in *other*.
  @[Primitive(:simd_compare)]
  def cmp_le(other : self) : SIMDVector(Bool, N)
  end

  # Returns a vector where each lane is `true` if the corresponding lane
  # in `self` is greater than the lane in *other*.
  @[Primitive(:simd_compare)]
  def cmp_gt(other : self) : SIMDVector(Bool, N)
  end

  # Returns a vector where each lane is `true` if the corresponding lane
  # in `self` is greater than or equal to the lane in *other*.
  @[Primitive(:simd_compare)]
  def cmp_ge(other : self) : SIMDVector(Bool, N)
  end

  # --- Bitwise Shifts (integer vectors only) ---

  # Returns a new vector where each lane is shifted left by the corresponding
  # lane in *other*.
  #
  # WARNING: The shift amount per lane must be less than the bit width of `T`.
  # Shifting by >= bit width is undefined behavior.
  @[Primitive(:simd_binary)]
  def unsafe_shl(other : self) : self
  end

  # Returns a new vector where each lane is shifted right by the corresponding
  # lane in *other*. For unsigned types this is a logical shift; for signed
  # types this is an arithmetic shift.
  #
  # WARNING: The shift amount per lane must be less than the bit width of `T`.
  # Shifting by >= bit width is undefined behavior.
  @[Primitive(:simd_binary)]
  def unsafe_shr(other : self) : self
  end

  # Returns a new vector with each lane shifted left by *amount*.
  def unsafe_shl(amount : T) : self
    unsafe_shl(SIMDVector(T, N).splat(amount))
  end

  # Returns a new vector with each lane shifted right by *amount*.
  def unsafe_shr(amount : T) : self
    unsafe_shr(SIMDVector(T, N).splat(amount))
  end

  # --- Memory Operations ---

  # Loads a vector from a raw pointer. The pointer does not need to be aligned
  # to the vector size.
  #
  # WARNING: The caller must ensure that at least `N * sizeof(T)` bytes are
  # readable starting from *ptr*.
  #
  # ```
  # arr = StaticArray[1_i32, 2_i32, 3_i32, 4_i32]
  # vec = SIMDVector(Int32, 4).unsafe_load(arr.to_unsafe)
  # vec[0] # => 1
  # ```
  @[Primitive(:simd_load)]
  def self.unsafe_load(ptr : Pointer(T)) : self
  end

  # Stores this vector to a raw pointer. The pointer does not need to be aligned
  # to the vector size.
  #
  # WARNING: The caller must ensure that at least `N * sizeof(T)` bytes are
  # writable starting from *ptr*.
  #
  # ```
  # vec = SIMDVector[1_i32, 2_i32, 3_i32, 4_i32]
  # arr = StaticArray(Int32, 4).new(0)
  # vec.unsafe_store(arr.to_unsafe)
  # arr[2] # => 3
  # ```
  @[Primitive(:simd_store)]
  def unsafe_store(ptr : Pointer(T)) : Nil
  end

  # --- Lane Selection ---

  # Returns a new vector where each lane is chosen from *if_true* or *if_false*
  # based on the corresponding lane in *mask*.
  #
  # ```
  # a = SIMDVector[1, 2, 3, 4]
  # b = SIMDVector[5, 6, 7, 8]
  # mask = a.cmp_lt(b)
  # result = SIMDVector(Int32, 4).select(mask, a, b)
  # # mask is all true, so result == a
  # ```
  @[Primitive(:simd_select)]
  def self.select(mask : SIMDVector(Bool, N), if_true : self, if_false : self) : self
  end

  # --- Reductions ---

  # Returns the sum of all lanes.
  #
  # ```
  # vec = SIMDVector[1, 2, 3, 4]
  # vec.reduce_add # => 10
  # ```
  @[Primitive(:simd_reduce_add)]
  def reduce_add : T
  end

  # --- Widening ---

  # Widens each lane to a larger integer type. For unsigned types, zero-extends;
  # for signed types, sign-extends.
  #
  # ```
  # narrow = SIMDVector[1_u8, 2_u8, 3_u8, 4_u8]
  # wide = narrow.widen(UInt16)
  # wide[0] # => 1_u16
  # ```
  @[Primitive(:simd_widen)]
  def widen(type : U.class) : SIMDVector(U, N) forall U
  end

  # --- Bitmask Extraction (Bool vectors only) ---

  # Converts a boolean vector to a scalar bitmask. Lane 0 maps to bit 0,
  # lane 1 maps to bit 1, and so on. Only meaningful on `SIMDVector(Bool, N)`.
  #
  # ```
  # a = SIMDVector[1, 2, 3, 4]
  # b = SIMDVector[1, 0, 3, 0]
  # mask = a.cmp_eq(b)  # => [true, false, true, false]
  # mask.bitmask        # => 0b0101 == 5
  # ```
  @[Primitive(:simd_bitmask)]
  def bitmask : UInt64
  end

  # --- Conversion ---

  # Copies the vector lanes into a `StaticArray`.
  #
  # ```
  # vec = SIMDVector[1, 2, 3, 4]
  # arr = vec.to_static_array
  # arr # => StaticArray[1, 2, 3, 4]
  # ```
  def to_static_array : StaticArray(T, N)
    array = uninitialized StaticArray(T, N)
    N.times do |i|
      array.to_unsafe[i] = unsafe_extract(i)
    end
    array
  end

  # Creates a `SIMDVector` from a `StaticArray`.
  #
  # ```
  # arr = StaticArray[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
  # vec = SIMDVector(Float32, 4).from_static_array(arr)
  # vec[0] # => 1.0
  # ```
  def self.from_static_array(array : StaticArray(T, N)) : self
    vec = uninitialized self
    N.times do |i|
      vec = vec.unsafe_insert(i, array.to_unsafe[i])
    end
    vec
  end

  # --- Equality ---

  # Returns `true` if all lanes of `self` and *other* are equal.
  def ==(other : self) : Bool
    N.times do |i|
      return false unless unsafe_extract(i) == other.unsafe_extract(i)
    end
    true
  end

  # --- Hashing ---

  def hash(hasher)
    N.times do |i|
      hasher = unsafe_extract(i).hash(hasher)
    end
    hasher
  end

  # --- Output ---

  def to_s(io : IO) : Nil
    io << "SIMDVector["
    N.times do |i|
      io << ", " if i > 0
      unsafe_extract(i).to_s(io)
    end
    io << ']'
  end

  def inspect(io : IO) : Nil
    to_s(io)
  end
end
