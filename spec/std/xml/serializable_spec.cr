require "../spec_helper"
require "xml"
require "json"
require "yaml"
{% unless flag?(:win32) %}
  require "big"
{% end %}
require "uuid"

class XMLAttrPerson
  include XML::Serializable

  property name : String
  property age : Int32?

  def_equals name, age

  def initialize(@name : String, @age : Int32)
  end
end

describe "XML mapping" do
  it "serializes" do
    XMLAttrPerson.new("John Snow", 18).to_xml.should eq "<?xml version=\"1.0\"?>\n<XMLAttrPerson><name>John Snow</name><age>18</age></XMLAttrPerson>\n"
  end
end
