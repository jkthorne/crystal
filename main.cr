require "xml"

text = <<-XML
<?xml version="1.0"?>
<XMLAttrPerson>
  <name>John Snow</name>
  <age>18</age>
</XMLAttrPerson>
XML

xml = XML::Reader.new(text)

p xml.next
p xml.expand
p xml.next
p xml.next
p xml.next
