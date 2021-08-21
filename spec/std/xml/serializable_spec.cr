require "../spec_helper"
require "xml"
require "xml/serializable"
# require "json"
# require "yaml"
# {% unless flag?(:win32) %}
#   require "big"
# {% end %}
# require "uuid"

# struct XMLAttrPerson
#   include XML::Serializable
#   property name : String
#   property age : Int32?
#   def_equals name, age
#   def initialize(@name : String, @age : Int32)
#   end
# end

record XMLAttrPoint, x : Int32, y : Int32 do
  include XML::Serializable
end

describe "XML mapping" do
  # it "serializes" do
  #   XMLAttrPerson.new("John Snow", 18).to_xml.should eq "<?xml version=\"1.0\"?>\n<XMLAttrPerson><name>John Snow</name><age>18</age></XMLAttrPerson>\n"
  # end

  it "works with record" do
    xml = "<?xml version=\"1.0\"?>\n<XMLAttrPoint x=1 y=2</XMLAttrPoint>\n"
    XMLAttrPoint.new(1, 2).to_xml.should eq xml
    # XMLAttrPoint.from_xml(xml).should eq XMLAttrPoint.new(1, 2)
  end
end
