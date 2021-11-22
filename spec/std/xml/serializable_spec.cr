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
    xml = %(<XMLAttrPoint><x>1</x><y>2</y></XMLAttrPoint>\n)
    XMLAttrPoint.new(1, 2).to_xml.should eq xml
    XMLAttrPoint.from_xml(xml).should eq XMLAttrPoint.new(1, 2)
  end

  it "empty class" do
    xml = %(<XMLAttrEmptyClass/>\n)
    XMLAttrEmptyClass.new.to_xml.should eq xml
    XMLAttrEmptyClass.from_xml xml
  end

  pending "empty class with unmapped" do
    xml = %(<XMLAttrEmptyClassWithUnmapped><name>John</name><age>30</age></XMLAttrEmptyClassWithUnmapped>\n)
    XMLAttrEmptyClassWithUnmapped.from_xml(xml).xml_unmapped.should eq({"name" => "John", "age" => 30})
  end

  it "parses person" do
    person = XMLAttrPerson.from_xml(%({"name": "John", "age": 30}))
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.age.should eq(30)
  end

  pending "parses person without age" do
    person = XMLAttrPerson.from_xml(%({"name": "John"}))
    person.should be_a(XMLAttrPerson)
    person.name.should eq("John")
    person.name.size.should eq(4) # This verifies that name is not nilable
    person.age.should be_nil
  end

  pending "parses array of people" do
    people = Array(JSONAttrPerson).from_xml(%([{"name": "John"}, {"name": "Doe"}]))
    people.size.should eq(2)
  end
end
