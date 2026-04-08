module BigNumber
  # The unsigned 64-bit type used as the fundamental building block for
  # multi-precision numbers. All BigInt values are stored as arrays of limbs
  # in least-significant-first order.
  alias Limb = UInt64

  # Signed variant of `Limb`, used in operations that require sign tracking
  # (e.g., size field encoding sign in its magnitude).
  alias SignedLimb = Int64

  # Number of bits per limb.
  LIMB_BITS = 64

  # Maximum value a single limb can hold (`2^64 - 1`).
  LIMB_MAX = Limb::MAX

  # Bitmask for the most significant bit of a limb (`2^63`).
  LIMB_HIGHBIT = 1_u64 << 63

  # Bump allocator for temporary limb arrays used in divide-and-conquer algorithms
  # (e.g., Burnikel-Ziegler division, recursive base conversion).
  #
  # Allocates a single contiguous block up front, then hands out zero-initialized
  # slices via `#alloc`. No per-buffer deallocation -- the entire arena is freed
  # when it goes out of scope (via GC).
  #
  # ```
  # arena = BigNumber::LimbArena.new(1024)
  # buf = arena.alloc(64) # => Pointer(UInt64) to 64 zeroed limbs
  # ```
  struct LimbArena
    @base : Pointer(Limb)
    @offset : Int32
    @capacity : Int32

    # Creates a new arena backed by a single allocation of *capacity* limbs.
    def initialize(capacity : Int32)
      @base = Pointer(Limb).malloc(capacity)
      @offset = 0
      @capacity = capacity
    end

    # Allocates *n* zero-initialized limbs from the arena.
    #
    # Raises if the arena does not have enough remaining capacity.
    def alloc(n : Int32) : Pointer(Limb)
      raise "LimbArena exhausted: need #{n}, have #{@capacity - @offset}" if @offset + n > @capacity
      ptr = @base + @offset
      ptr.clear(n)
      @offset += n
      ptr
    end
  end
end
