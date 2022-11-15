require "./src/xml"

x = 1
y = 2

puts "hello world"

text = <<-XML
<?xml version="1.0"?>
<XMLAttrPerson>
  <name>John Snow</name>
  <age>18</age>
</XMLAttrPerson>
XML

parser = XML::PullParser.new(text)
p parser.raw_value
p parser.string_value
parser.read_raw
p parser.raw_value
p parser.int_value
