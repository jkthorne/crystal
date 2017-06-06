require "spec"
require "uuid"

describe "UUID" do
  it "returns nil UUID" do
    UUID.empty.to_s.should eq "00000000-0000-0000-0000-000000000000"
    UUID.empty.variant.should eq UUID::Variant::NCS
  end

  it "generates random UUID V4" do
    uuid = UUID.random
    uuid.variant.should eq(UUID::Variant::RFC4122)
    uuid.version.should eq(UUID::Version::V4)
  end

  it "creates custom UUID" do
    bytes = StaticArray(UInt8, 16).new { |i| (i + 1).to_u8 }
    UUID.new(bytes).to_s.should eq("01020304-0506-0708-090a-0b0c0d0e0f10")
  end

  it "creates custom UUID with variant and version" do
    bytes = StaticArray(UInt8, 16).new { |i| (i + 1).to_u8 }
    uuid = UUID.new(bytes, UUID::Variant::Microsoft, UUID::Version::V1)
    uuid.to_s.should eq("01020304-0506-1708-c90a-0b0c0d0e0f10")
  end

  it "#to_slice" do
    bytes = StaticArray(UInt8, 16).new { |i| (i + 1).to_u8 }
    uuid = UUID.new(bytes)
    uuid.to_slice.should eq(bytes.to_slice)
  end

  describe "#decode" do
    it "creates UUID from string" do
      UUID.new("c20335c3-7f46-4126-aae9-f665434ad12b").should eq("c20335c3-7f46-4126-aae9-f665434ad12b")
      UUID.new("c20335c37f464126aae9f665434ad12b").should eq("c20335c3-7f46-4126-aae9-f665434ad12b")
      UUID.new("C20335C3-7F46-4126-AAE9-F665434AD12B").should eq("c20335c3-7f46-4126-aae9-f665434ad12b")
      UUID.new("C20335C37F464126AAE9F665434AD12B").should eq("c20335c3-7f46-4126-aae9-f665434ad12b")
    end

    it "decodes variant and version" do
      uuid = UUID.new("C20335C37F464126AAE9F665434AD12B")
      uuid.variant.should eq(UUID::Variant::RFC4122)
      uuid.version.should eq(UUID::Version::V4)
    end

    it "fails on invalid formats" do
      expect_raises(ArgumentError) { UUID.new "" }
      expect_raises(ArgumentError) { UUID.new "25d6f843?cf8e-44fb-9f84-6062419c4330" }
      expect_raises(ArgumentError) { UUID.new "67dc9e24-0865 474b-9fe7-61445bfea3b5" }
      expect_raises(ArgumentError) { UUID.new "5942cde5-10d1-416b+85c4-9fc473fa1037" }
      expect_raises(ArgumentError) { UUID.new "0f02a229-4898-4029-926f=94be5628a7fd" }
      expect_raises(ArgumentError) { UUID.new "cda08c86-6413-474f-8822-a6646e0fb19G" }
      expect_raises(ArgumentError) { UUID.new "2b1bfW06368947e59ac07c3ffdaf514c" }
    end
  end

  it "compares to strings" do
    uuid = UUID.new("c3b46146eb794e18877b4d46a10d1517")
    uuid.should eq("c3b46146eb794e18877b4d46a10d1517")
    uuid.should eq("c3b46146-eb79-4e18-877b-4d46a10d1517")
    uuid.should eq("C3B46146-EB79-4E18-877B-4D46A10D1517")
    uuid.should eq("urn:uuid:C3B46146-EB79-4E18-877B-4D46A10D1517")
    uuid.should eq("urn:uuid:c3b46146-eb79-4e18-877b-4d46a10d1517")

    uuid.should_not eq("A3b46146eb794e18877b4d46a10d1517")
    uuid.should_not eq("a3b46146eb794e18877b4d46a10d1517")
    uuid.should_not eq("a3b46146-eb79-4e18-877b-4d46a10d1517")
    uuid.should_not eq("urn:uuid:a3b46146-eb79-4e18-877b-4d46a10d1517")
  end

  it "fails when comparing to invalid strings" do
    expect_raises(ArgumentError) { UUID.random == "" }
    expect_raises(ArgumentError) { UUID.random == "d1fb9189-7013-4915-a8b1-07cfc83bca3U" }
    expect_raises(ArgumentError) { UUID.random == "2ab8ffc8f58749e197eda3e3d14e0 6c" }
    expect_raises(ArgumentError) { UUID.random == "2ab8ffc8f58749e197eda3e3d14e 06c" }
    expect_raises(ArgumentError) { UUID.random == "2ab8ffc8f58749e197eda3e3d14e-76c" }
  end

  it "handles variant" do
    uuid = UUID.random
    expect_raises(ArgumentError) { uuid.variant = UUID::Variant::Unknown }
    {% for variant in %w(NCS RFC4122 Microsoft Future) %}
      uuid.variant = UUID::Variant::{{ variant.id }}
      uuid.variant.should eq UUID::Variant::{{ variant.id }}
    {% end %}
  end

  it "handles version" do
    uuid = UUID.random
    expect_raises(ArgumentError) { uuid.version = UUID::Version::Unknown }
    {% for version in %w(1 2 3 4 5) %}
      uuid.version = UUID::Version::V{{ version.id }}
      uuid.version.should eq UUID::Version::V{{ version.id }}
      uuid.v{{ version.id }}?.should be_true
    {% end %}
  end

  it "formats hyphenated string" do
    UUID.new("ee843b2656d8472bb3430b94ed9077ff").to_s.should eq("ee843b26-56d8-472b-b343-0b94ed9077ff")
  end

  it "formats UUID to IO" do
    uuid = UUID.new("c3b46146eb794e18877b4d46a10d1517")
    io = IO::Memory.new(36)
    uuid.to_s(io)
    io.rewind.to_s.should eq("c3b46146-eb79-4e18-877b-4d46a10d1517")
  end

  it "formats hexstring" do
    UUID.new("3e806983-eca4-4fc5-b581-f30fb03ec9e5").hexstring.should eq("3e806983eca44fc5b581f30fb03ec9e5")
  end

  it "formats URN" do
    UUID.new("1ed1ee2f-ef9a-4f9c-9615-ab14d8ef2892").urn.should eq("urn:uuid:1ed1ee2f-ef9a-4f9c-9615-ab14d8ef2892")
  end
end
