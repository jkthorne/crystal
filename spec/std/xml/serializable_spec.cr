require "../spec_helper"
require "xml"
require "uuid"

record XMLAttrPoint, x : Int32, y : Int32 do
  include XML::Serializable
end

class XMLAttrEmptyClass
  include XML::Serializable

  def initialize; end
end

class XMLAttrEmptyClassWithUnmapped
  include XML::Serializable
  include XML::Serializable::Unmapped

  def initialize; end
end

class XMLAttrPerson
  include XML::Serializable

  property name : String
  property age : Int32?

  def_equals name, age

  def initialize(@name : String)
  end
end

struct XMLAttrPersonWithTwoFieldInInitialize
  include XML::Serializable

  property name : String
  property age : Int32

  def initialize(@name, @age)
  end
end

class StrictXMLAttrPerson
  include XML::Serializable
  include XML::Serializable::Strict

  property name : String
  property age : Int32?
end

class XMLAttrPersonExtraFields
  include XML::Serializable
  include XML::Serializable::Unmapped

  property name : String
  property age : Int32?
end

class XMLAttrPersonEmittingNull
  include XML::Serializable

  property name : String

  @[XML::Element(emit_null: true)]
  property age : Int32?
end

@[XML::Serializable::Options(emit_nulls: true)]
class XMLAttrPersonEmittingNullsByOptions
  include XML::Serializable

  property name : String
  property age : Int32?
  property value1 : Int32?

  @[XML::Element(emit_null: false)]
  property value2 : Int32?
end

class XMLAttrWithBool
  include XML::Serializable

  property value : Bool
end

class XMLAttrWithUUID
  include XML::Serializable

  property value : UUID
end

# class XMLAttrWithBigDecimal
#   include XML::Serializable

#   property value : BigDecimal
# end

class XMLAttrWithSimpleMapping
  include XML::Serializable

  property name : String
  property age : Int32
end

class XMLAttrWithTime
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F %T"))]
  property value : Time
end

class XMLAttrWithNilableTime
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F"))]
  property value : Time?

  def initialize
  end
end

class XMLAttrWithNilableTimeEmittingNull
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F"), emit_null: true)]
  property value : Time?

  def initialize
  end
end

class XMLAttrWithPropertiesKey
  include XML::Serializable

  property properties : Hash(String, String)
end

class XMLAttrWithKeywordsMapping
  include XML::Serializable

  property end : Int32
  property abstract : Int32
end

class XMLAttrWithProblematicKeys
  include XML::Serializable

  property key : Int32
  property pull : Int32
end

class XMLAttrWithSet
  include XML::Serializable

  property set : Set(String)
end

class XMLAttrWithSmallIntegers
  include XML::Serializable

  property foo : Int16
  property bar : Int8
end

class XMLAttrWithDefaults
  include XML::Serializable

  property a = 11
  property b = "Haha"
  property c = true
  property d = false
  property e : Bool? = false
  property f : Int32? = 1
  property g : Int32?
  property h = [1, 2, 3]
end

describe "XML mapping" do
  it "works with record" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPoint><x>1</x><y>2</y></XMLAttrPoint>\n
      XML

    XMLAttrPoint.new(1, 2).to_xml.should eq(xml)
    XMLAttrPoint.from_xml(xml).should eq(XMLAttrPoint.new(1, 2))
  end

  it "empty class" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrEmptyClass/>\n
      XML

    e = XMLAttrEmptyClass.new
    e.to_xml.should eq(xml)
    XMLAttrEmptyClass.from_xml(xml)
  end

  it "empty class with unmapped" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrEmptyClassWithUnmapped>
        <name>John</name>
        <age>30</age>
      </XMLAttrEmptyClassWithUnmapped>\n
      XML

    XMLAttrEmptyClassWithUnmapped.from_xml(xml).xml_unmapped.should eq(
      {
        "name" => XML::Any.new("John"),
        "age"  => XML::Any.new("30"),
      }
    )
  end

  it "parses person" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
      </XMLAttrPerson>\n
      XML

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "parses person without age" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
      </XMLAttrPerson>\n
      XML

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.name.size.should eq(4) # This verifies that name is not nilable
    person.age.should be_nil
  end

  it "parses array of people" do
    xml = <<-XML
      <?xml version="1.0"?>
      <array>
        <XMLAttrPerson>
          <name>John</name>
        </XMLAttrPerson>
        <XMLAttrPerson>
          <name>Doe</name>
        </XMLAttrPerson>\n
      </array>
      XML

    people = Array(XMLAttrPerson).from_xml(xml)
    people.size.should eq(2)
  end

  it "works with class with two fields" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
      </XMLAttrPerson>\n
      XML

    person1 = XMLAttrPersonWithTwoFieldInInitialize.from_xml(xml)
    person2 = XMLAttrPersonWithTwoFieldInInitialize.new("John", 30)
    person1.should eq person2
  end

  it "does to_xml" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
      </XMLAttrPerson>\n
      XML

    person = XMLAttrPerson.from_xml(xml)
    person2 = XMLAttrPerson.from_xml(person.to_xml)
    person2.should eq(person)
  end

  it "parses person with unknown attributes" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
        <foo>bar</foo>
      </XMLAttrPerson>\n
      XML

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  pending "parses strict person with unknown attributes" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
        <foo>bar</foo>
      </XMLAttrPerson>\n
      XML

    error_message = <<-'MSG'
      Unknown XML attribute: foo
        parsing StrictXMLAttrPerson
      MSG

    ex = expect_raises ::XML::SerializableError, error_message do
      StrictXMLAttrPerson.from_xml(xml)
    end
    # ex.location.should eq({4, 3}) TODO: implement location
  end

  pending "should parse extra fields (XMLAttrPersonExtraFields with on_unknown_xml_attribute)" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPersonExtraFields>
        <name>John</name>
        <age>30</age>
        <x>1</x>
        <y>2</y>
      </XMLAttrPersonExtraFields>\n
      XML
    # TODO: <z>1,2,3</z>

    person = XMLAttrPersonExtraFields.from_xml xml
    person.name.should eq("John")
    person.age.should eq(30)
    # TODO: "z" => [1, 2, 3]
    person.xml_unmapped.should eq({"x" => "1", "y" => 2_i64})
  end

  pending "should to store extra fields (XMLAttrPersonExtraFields with on_to_xml)" do
    original_xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPersonExtraFields>
        <name>John</name>
        <age>30</age>
        <x>1</x>
        <y>2</y>
      </XMLAttrPersonExtraFields>\n
      XML
    # TODO: <z>1,2,3</z>
    expected_xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPersonExtraFields>
        <name>John1</name>
        <age>30</age>
        <x>1</x>
        <y>2</y>
        <q>w</q>
      </XMLAttrPersonExtraFields>\n
      XML

    person = XMLAttrPersonExtraFields.from_xml(original_xml)
    person.name = "John1"
    person.xml_unmapped.delete("y")
    person.xml_unmapped["q"] = XML::Any.new("w")
    # TODO: "z" => [1, 2, 3]
    person.to_xml.should eq expected_xml
  end

  pending "raises if non-nilable attribute is nil" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <age>30</age>
      </XMLAttrPerson>\n
      XML

    error_message = <<-'MSG'
      Missing XML attribute: name
        parsing XMLAttrPerson at line 1, column 1
      MSG

    ex = expect_raises ::XML::SerializableError, error_message do
      XMLAttrPerson.from_xml(xml)
    end
    # TODO: ex.location.should eq({1, 1})
  end

  pending "raises if not an object" do
    error_message = <<-'MSG'
      Expected BeginObject but was String at line 1, column 1
        parsing StrictXMLAttrPerson at line 0, column 0
      MSG
    ex = expect_raises ::XML::SerializableError, error_message do
      StrictXMLAttrPerson.from_xml <<-XML
        "foo"
        XML
    end
    # ex.location.should eq({1, 1})
  end

  pending "raises if data type does not match" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
        <foo>bar</foo>
      </XMLAttrPerson>\n
      XML

    error_message = <<-MSG
      Couldn't parse (Int32 | Nil) from "foo" at line 3, column 10
      MSG
    ex = expect_raises ::XML::SerializableError, error_message do
      StrictXMLAttrPerson.from_xml xml
    end
    # ex.location.should eq({3, 10})
  end

  pending "doesn't emit null by default when doing to_xml" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
      </XMLAttrPerson>\n
      XML

    person = XMLAttrPerson.from_xml(xml)
    (person.to_xml =~ /age/).should be_falsey
  end

  it "emits null on request when doing to_xml" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPersonEmittingNull>
        <name>John</name>
      </XMLAttrPersonEmittingNull>\n
      XML

    person = XMLAttrPersonEmittingNull.from_xml(xml)
    (person.to_xml =~ /age/).should be_truthy
  end

  it "emit_nulls option" do
    original_xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
      </XMLAttrPerson>\n
      XML

    expected_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrPersonEmittingNullsByOptions>"
      str << "<name>John</name><age/><value1/><value2/>"
      str << "</XMLAttrPersonEmittingNullsByOptions>\n"
    end

    person = XMLAttrPersonEmittingNullsByOptions.from_xml(original_xml)
    person.to_xml.should eq expected_xml
  end

  it "doesn't raises on false value when not-nil" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithBool>
        <value>false</value>
      </XMLAttrWithBool>\n
      XML

    xml = XMLAttrWithBool.from_xml(xml)
    xml.value.should be_false
  end

  it "parses UUID" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithBool>
        <value>ba714f86-cac6-42c7-8956-bcf5105e1b81</value>
      </XMLAttrWithBool>\n
      XML

    uuid = XMLAttrWithUUID.from_xml(xml)
    uuid.should be_a(XMLAttrWithUUID)
    uuid.value.should eq(UUID.new("ba714f86-cac6-42c7-8956-bcf5105e1b81"))
  end

  it "parses xml with Time::Format converter" do
    original_xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithTime>
        <value>2014-10-31 23:37:16</value>
      </XMLAttrWithTime>\n
      XML

    expected_xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithTime>"
      str << "<value>2014-10-31 23:37:16 UTC</value>" # NOTE: should this include `UTC`
      str << "</XMLAttrWithTime>\n"
    end

    xml = XMLAttrWithTime.from_xml(original_xml)
    xml.value.should be_a(Time)
    xml.value.to_s.should eq("2014-10-31 23:37:16 UTC")
    xml.to_xml.should eq(expected_xml)
  end

  it "allows setting a nilable property to nil" do
    person = XMLAttrPerson.new("John")
    person.age = 1
    person.age = nil
  end

  it "parses simple mapping" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrPerson>
        <name>John</name>
        <age>30</age>
      </XMLAttrPerson>\n
      XML

    person = XMLAttrWithSimpleMapping.from_xml(xml)
    person.should be_a(XMLAttrWithSimpleMapping)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  it "outputs with converter when nilable" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithNilableTime>"
      str << "<value/>"
      str << "</XMLAttrWithNilableTime>\n"
    end

    obj = XMLAttrWithNilableTime.new
    obj.to_xml.should eq(xml)
  end

  it "outputs with converter when nilable when emit_null is true" do
    xml = String.build do |str|
      str << "<?xml version=\"1.0\"?>\n"
      str << "<XMLAttrWithNilableTimeEmittingNull>"
      str << "<value/>"
      str << "</XMLAttrWithNilableTimeEmittingNull>\n"
    end

    obj = XMLAttrWithNilableTimeEmittingNull.new
    obj.to_xml.should eq(xml)
  end

  # TODO: implement Hash.to_xml
  # it "outputs JSON with properties key" do
  #   xml = String.build do |str|
  #     str << "<?xml version=\"1.0\"?>\n"
  #     str << "<XMLAttrWithKeywordsMapping>"
  #     str << "<properties>"
  #     str << "<foo>bar</foo>"
  #     str << "</properties>"
  #     str << "</XMLAttrWithKeywordsMapping>\n"
  #   end

  #   obj = XMLAttrWithPropertiesKey.from_xml(xml)
  #   obj.to_xml.should eq(xml)
  # end

  it "parses xml with keywords" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithKeywordsMapping>
        <end>1</end>
        <abstract>2</abstract>
      </XMLAttrWithKeywordsMapping>\n
      XML

    obj = XMLAttrWithKeywordsMapping.from_xml(xml)
    obj.end.should eq(1)
    obj.abstract.should eq(2)
  end

  # it "parses json with any" do
  #   xml = String.build do |str|
  #     str << "<?xml version=\"1.0\"?>"
  #     str << "<XMLAttrWithAny>"
  #     str << "<name>John</name>"
  #     str << "<any>"
  #     str << "<value><x>1</x></value>"
  #     str << "<value>2</value>"
  #     str << "<value>hey</value>"
  #     str << "<value>true</value>"
  #     str << "<value>false</value>"
  #     str << "<value>1.5</value>"
  #     str << "<value>null<value>"
  #     str << "</any>"
  #     str << "</XMLAttrWithAny>\n"
  #   end
  #   obj = XMLAttrWithAny.from_xml(xml)
  #   obj.name.should eq("John")
  #   obj.any.raw.should eq([{"x" => 1}, 2, "hey", true, false, 1.5, nil])
  #   obj.to_xml.should eq(%({"name":"Hi","any":[{"x":1},2,"hey",true,false,1.5,null]}))
  # end

  it "parses xml with problematic keys" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithProblematicKeys>
        <key>1</key>
        <pull>2</pull>
      </XMLAttrWithProblematicKeys>
      XML

    obj = XMLAttrWithProblematicKeys.from_xml(xml)
    obj.key.should eq(1)
    obj.pull.should eq(2)
  end

  pending "parses xml array as set" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithSet>
        <set>
          <value>a</value>
          <value>a</value>
          <value>b</value>
        </set>
      </XMLAttrWithSet>
      XML

    obj = XMLAttrWithSet.from_xml(xml)
    obj.set.should eq(Set(String){"a", "b"})
  end

  pending "allows small types of integer" do
    xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithSmallIntegers>
        <foo>1</foo>
        <bar>2</bar>
      </XMLAttrWithSmallIntegers>
      XML

    obj = XMLAttrWithSmallIntegers.from_xml(xml)

    typeof(obj.foo).should eq(Int16)
    obj.foo.should eq(23)

    typeof(obj.bar).should eq(Int8)
    obj.bar.should eq(7)
  end

  describe "parses json with defaults" do
    it "mixed" do
      xml_1 = <<-XML
        <?xml version="1.0"?>
        <XMLAttrWithSmallIntegers>
          <a>1</a>
          <b>2</b>
        </XMLAttrWithSmallIntegers>
        XML

      obj = XMLAttrWithDefaults.from_xml(xml_1)
      obj.a.should eq 1
      obj.b.should eq "bla"

      # xml = XMLAttrWithDefaults.from_xml(%({"a":1}))
      # xml.a.should eq 1
      # xml.b.should eq "Haha"

      # xml = XMLAttrWithDefaults.from_xml(%({"b":"bla"}))
      # xml.a.should eq 11
      # xml.b.should eq "bla"

      # xml = XMLAttrWithDefaults.from_xml(%({}))
      # xml.a.should eq 11
      # xml.b.should eq "Haha"

      # xml = XMLAttrWithDefaults.from_xml(%({"a":null,"b":null}))
      # xml.a.should eq 11
      # xml.b.should eq "Haha"
    end

    #   it "bool" do
    #     json = JSONAttrWithDefaults.from_json(%({}))
    #     json.c.should eq true
    #     typeof(json.c).should eq Bool
    #     json.d.should eq false
    #     typeof(json.d).should eq Bool

    #     json = JSONAttrWithDefaults.from_json(%({"c":false}))
    #     json.c.should eq false
    #     json = JSONAttrWithDefaults.from_json(%({"c":true}))
    #     json.c.should eq true

    #     json = JSONAttrWithDefaults.from_json(%({"d":false}))
    #     json.d.should eq false
    #     json = JSONAttrWithDefaults.from_json(%({"d":true}))
    #     json.d.should eq true
    #   end

    #   it "with nilable" do
    #     json = JSONAttrWithDefaults.from_json(%({}))

    #     json.e.should eq false
    #     typeof(json.e).should eq(Bool | Nil)

    #     json.f.should eq 1
    #     typeof(json.f).should eq(Int32 | Nil)

    #     json.g.should eq nil
    #     typeof(json.g).should eq(Int32 | Nil)

    #     json = JSONAttrWithDefaults.from_json(%({"e":false}))
    #     json.e.should eq false
    #     json = JSONAttrWithDefaults.from_json(%({"e":true}))
    #     json.e.should eq true
    #   end

    #   it "create new array every time" do
    #     json = JSONAttrWithDefaults.from_json(%({}))
    #     json.h.should eq [1, 2, 3]
    #     json.h << 4
    #     json.h.should eq [1, 2, 3, 4]

    #     json = JSONAttrWithDefaults.from_json(%({}))
    #     json.h.should eq [1, 2, 3]
    #   end
  end
end
