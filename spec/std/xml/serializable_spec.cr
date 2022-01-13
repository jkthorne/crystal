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
      <XMLAttrEmptyClass/>

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
      </XMLAttrEmptyClassWithUnmapped>

      XML

    XMLAttrEmptyClassWithUnmapped.from_xml(xml).xml_unmapped.should eq(
      {
        "name" => XML::Any.new("John"),
        "age"  => XML::Any.new("30"),
        "text" => XML::Any.new("\n"),
      }
    )
  end

  it "parses person" do
    xml = <<-XML
        <?xml version="1.0"?>
        <XMLAttrPerson>
          <name>John</name>
          <age>30</age>
        </XMLAttrPerson>

      XML

    person = XMLAttrPerson.from_xml(xml)
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  # pending "parses person without age" do
  #   person = XMLAttrPerson.from_xml(%({"name": "John"}))
  #   person.should be_a(XMLAttrPerson)
  #   person.name.should eq("John")
  #   person.name.size.should eq(4) # This verifies that name is not nilable
  #   person.age.should be_nil
  # end

  # pending "parses array of people" do
  #   people = Array(JSONAttrPerson).from_xml(%([{"name": "John"}, {"name": "Doe"}]))
  #   people.size.should eq(2)
  # end
end
