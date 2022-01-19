require "../spec_helper"
require "xml"

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

  it "parses strict person with unknown attributes" do
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
end
