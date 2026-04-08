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

  context "string output" do
    it "renders with to_s" do
      SIMDVector[1, 2].to_s.should eq("SIMDVector[1, 2]")
    end

    it "renders with inspect" do
      SIMDVector[1.0_f32, 2.0_f32].inspect.should eq("SIMDVector[1.0, 2.0]")
    end
  end
end
