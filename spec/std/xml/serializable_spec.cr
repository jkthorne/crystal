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

class XMLAttrWithTime
  include XML::Serializable

  @[XML::Element(converter: Time::Format.new("%F %T"))]
  property value : Time
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

    expected_xml = <<-XML
      <?xml version="1.0"?>
      <XMLAttrWithTime>
        <value>2014-10-31 23:37:16</value>
      </XMLAttrWithTime>\n
      XML

    xml = XMLAttrWithTime.from_xml(original_xml)
    xml.value.should be_a(Time)
    xml.value.to_s.should eq("2014-10-31 23:37:16 UTC")
    xml.to_xml.should eq(expected_xml)
  end
end
