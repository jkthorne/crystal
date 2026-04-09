require "spec"
require "simd_vector"

private def vector_values(vec)
  Array(typeof(vec.unsafe_extract(0))).new(vec.size) do |i|
    vec.unsafe_extract(i)
  end
end

describe SIMDVector do
  context "construction" do
    it "builds from literal macro" do
      vec = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
      vector_values(vec).should eq([1.0, 2.0, 3.0, 4.0])
      vec.size.should eq(4)
    end

    it "builds with splat" do
      vec = SIMDVector(Int32, 4).splat(7)
      vector_values(vec).should eq([7, 7, 7, 7])
    end

    it "builds with zero" do
      vec = SIMDVector(Float64, 2).zero
      vector_values(vec).should eq([0.0, 0.0])
    end

    it "supports unsafe extract and insert" do
      vec = SIMDVector(Int8, 4).splat(1)
      vec = vec.unsafe_insert(2, 9_i8)
      vec.unsafe_extract(2).should eq(9)
    end

    it "checks bounds on []" do
      vec = SIMDVector(Int32, 4).splat(0)
      vec[1].should eq(0)
      expect_raises(IndexError) { vec[4] }
    end
  end

  context "arithmetic" do
    it "adds, subtracts, multiplies, and divides vectors" do
      a = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
      b = SIMDVector[4.0_f32, 3.0_f32, 2.0_f32, 1.0_f32]
      vector_values(a + b).should eq([5.0, 5.0, 5.0, 5.0])
      vector_values(a - b).should eq([-3.0, -1.0, 1.0, 3.0])
      vector_values(a * b).should eq([4.0, 6.0, 6.0, 4.0])
      vector_values((a + SIMDVector(Float32, 4).splat(1.0)) / b).should eq([0.5, 1.0, 2.0, 5.0])
    end

    it "performs scalar operations" do
      vec = SIMDVector(Int64, 2).splat(3)
      vector_values(vec + 2).should eq([5, 5])
      vector_values(vec - 1).should eq([2, 2])
      vector_values(vec * 4).should eq([12, 12])
      vector_values(vec / 3).should eq([1, 1])
    end

    it "performs bitwise operations" do
      a = SIMDVector(Int16, 4).splat(0b1010)
      b = SIMDVector(Int16, 4).splat(0b1100)
      vector_values(a & b).should eq([0b1000] * 4)
      vector_values(a | b).should eq([0b1110] * 4)
      vector_values(a ^ b).should eq([0b0110] * 4)
    end
  end

  context "comparisons" do
    it "compares vectors lane-wise" do
      a = SIMDVector[1, 2, 3, 4]
      b = SIMDVector[2, 2, 1, 4]
      vector_values(a.cmp_eq(b)).should eq([false, true, false, true])
      vector_values(a.cmp_ne(b)).should eq([true, false, true, false])
      vector_values(a.cmp_lt(b)).should eq([true, false, false, false])
      vector_values(a.cmp_le(b)).should eq([true, true, false, true])
      vector_values(a.cmp_gt(b)).should eq([false, false, true, false])
      vector_values(a.cmp_ge(b)).should eq([false, true, true, true])
    end
  end

  context "conversion and equality" do
    it "converts to and from StaticArray" do
      array = StaticArray[1, 2, 3, 4]
      vec = SIMDVector(Int32, 4).from_static_array(array)
      vec.to_static_array.should eq(array)
    end

    it "checks equality lane-wise" do
      a = SIMDVector[1, 2, 3, 4]
      b = SIMDVector[1, 2, 3, 4]
      c = SIMDVector[1, 2, 0, 4]
      (a == b).should be_true
      (a == c).should be_false
    end

    it "hashes based on lanes" do
      hash = {} of SIMDVector(Int32, 4) => Int32
      vec = SIMDVector[1, 2, 3, 4]
      hash[vec] = 1
      hash.has_key?(SIMDVector[1, 2, 3, 4]).should be_true
      hash.has_key?(SIMDVector[0, 2, 3, 4]).should be_false
    end
  end

  context "bitwise shifts" do
    it "shifts left per-lane" do
      vec = SIMDVector[1_u32, 2_u32, 4_u32, 8_u32]
      shift = SIMDVector[1_u32, 2_u32, 3_u32, 0_u32]
      result = vec.unsafe_shl(shift)
      vector_values(result).should eq([2_u32, 8_u32, 32_u32, 8_u32])
    end

    it "shifts right per-lane" do
      vec = SIMDVector[16_u32, 32_u32, 64_u32, 128_u32]
      shift = SIMDVector[1_u32, 2_u32, 3_u32, 4_u32]
      result = vec.unsafe_shr(shift)
      vector_values(result).should eq([8_u32, 8_u32, 8_u32, 8_u32])
    end

    it "shifts by scalar amount" do
      vec = SIMDVector[1_u32, 2_u32, 3_u32, 4_u32]
      vector_values(vec.unsafe_shl(2_u32)).should eq([4_u32, 8_u32, 12_u32, 16_u32])
      vector_values(vec.unsafe_shr(1_u32)).should eq([0_u32, 1_u32, 1_u32, 2_u32])
    end
  end

  context "memory operations" do
    it "loads and stores via pointer roundtrip" do
      arr = StaticArray[10_i32, 20_i32, 30_i32, 40_i32]
      vec = SIMDVector(Int32, 4).unsafe_load(arr.to_unsafe)
      vector_values(vec).should eq([10, 20, 30, 40])

      out = StaticArray(Int32, 4).new(0)
      vec.unsafe_store(out.to_unsafe)
      out.to_a.should eq([10, 20, 30, 40])
    end

    it "handles unaligned loads from byte slice" do
      # Create a buffer with offset to test unaligned access
      buf = Bytes.new(20, 0_u8)
      4.times { |i| buf[1 + i] = (i + 1).to_u8 }
      vec = SIMDVector(UInt8, 4).unsafe_load(buf.to_unsafe + 1)
      vector_values(vec).should eq([1_u8, 2_u8, 3_u8, 4_u8])
    end

    it "loads and stores UInt16 vectors" do
      arr = StaticArray[100_u16, 200_u16, 300_u16, 400_u16, 500_u16, 600_u16, 700_u16, 800_u16]
      vec = SIMDVector(UInt16, 8).unsafe_load(arr.to_unsafe)
      vector_values(vec).should eq([100_u16, 200_u16, 300_u16, 400_u16, 500_u16, 600_u16, 700_u16, 800_u16])

      out = StaticArray(UInt16, 8).new(0_u16)
      vec.unsafe_store(out.to_unsafe)
      out.to_a.should eq([100, 200, 300, 400, 500, 600, 700, 800])
    end
  end

  context "select" do
    it "selects lanes based on mask" do
      a = SIMDVector[1, 2, 3, 4]
      b = SIMDVector[5, 6, 7, 8]
      mask = a.cmp_lt(SIMDVector[3, 3, 3, 3]) # [true, true, false, false]
      result = SIMDVector(Int32, 4).select(mask, a, b)
      vector_values(result).should eq([1, 2, 7, 8])
    end

    it "selects all from if_true when mask is all true" do
      a = SIMDVector[10, 20, 30, 40]
      b = SIMDVector[50, 60, 70, 80]
      mask = a.cmp_lt(b) # all true
      result = SIMDVector(Int32, 4).select(mask, a, b)
      vector_values(result).should eq([10, 20, 30, 40])
    end
  end

  context "reduce_add" do
    it "sums integer lanes" do
      vec = SIMDVector[1, 2, 3, 4]
      vec.reduce_add.should eq(10)
    end

    it "sums UInt16 lanes" do
      vec = SIMDVector[100_u16, 200_u16, 300_u16, 400_u16]
      vec.reduce_add.should eq(1000_u16)
    end

    it "sums float lanes" do
      vec = SIMDVector[1.0_f32, 2.0_f32, 3.0_f32, 4.0_f32]
      vec.reduce_add.should eq(10.0_f32)
    end

    it "sums zero vector" do
      SIMDVector(Int32, 4).zero.reduce_add.should eq(0)
    end
  end

  context "widen" do
    it "widens UInt8 to UInt16" do
      narrow = SIMDVector[1_u8, 2_u8, 255_u8, 0_u8]
      wide = narrow.widen(UInt16)
      vector_values(wide).should eq([1_u16, 2_u16, 255_u16, 0_u16])
    end

    it "widens Int8 to Int16 with sign extension" do
      narrow = SIMDVector[1_i8, -1_i8, 127_i8, -128_i8]
      wide = narrow.widen(Int16)
      vector_values(wide).should eq([1_i16, -1_i16, 127_i16, -128_i16])
    end

    it "widens UInt16 to UInt32" do
      narrow = SIMDVector[1000_u16, 65535_u16, 0_u16, 42_u16]
      wide = narrow.widen(UInt32)
      vector_values(wide).should eq([1000_u32, 65535_u32, 0_u32, 42_u32])
    end
  end

  context "bitmask" do
    it "extracts bitmask from comparison" do
      a = SIMDVector[1, 2, 3, 4]
      b = SIMDVector[1, 0, 3, 0]
      mask = a.cmp_eq(b)
      mask.bitmask.should eq(0b0101_u64)
    end

    it "returns 0 when all lanes are false" do
      a = SIMDVector[1, 2, 3, 4]
      b = SIMDVector[5, 6, 7, 8]
      a.cmp_eq(b).bitmask.should eq(0_u64)
    end

    it "returns all-ones when all lanes are true" do
      a = SIMDVector[1, 2, 3, 4]
      a.cmp_eq(a).bitmask.should eq(0b1111_u64)
    end

    it "works with 8-lane vectors" do
      a = SIMDVector[1_u16, 0_u16, 1_u16, 0_u16, 1_u16, 0_u16, 1_u16, 0_u16]
      zero = SIMDVector(UInt16, 8).zero
      mask = a.cmp_ne(zero)
      mask.bitmask.should eq(0b01010101_u64)
    end

    it "works with 16-lane byte vectors" do
      a = SIMDVector[1_u8, 2_u8, 3_u8, 4_u8, 5_u8, 6_u8, 7_u8, 8_u8,
                     9_u8, 10_u8, 11_u8, 12_u8, 13_u8, 14_u8, 15_u8, 16_u8]
      b = SIMDVector[1_u8, 2_u8, 0_u8, 4_u8, 5_u8, 6_u8, 0_u8, 8_u8,
                     9_u8, 10_u8, 11_u8, 12_u8, 13_u8, 14_u8, 15_u8, 16_u8]
      ne_mask = a.cmp_ne(b).bitmask
      # Lanes 2 and 6 differ
      ne_mask.should eq((1_u64 << 2) | (1_u64 << 6))
    end
  end

  context "string output" do
    it "renders with to_s" do
      SIMDVector[1, 2].to_s.should eq("SIMDVector[1, 2]")
    end

    it "renders with inspect" do
      SIMDVector[1.0_f32, 2.0_f32].inspect.should eq("SIMDVector[1.0, 2.0]")
    end
  end
end
