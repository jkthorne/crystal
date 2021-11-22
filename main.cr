require "json"
require "xml"

# pull = JSON::PullParser.new(%({"foo" : 1}))
# pull.read_begin_object
# pull.read_object_key

# p pull
# p ::Union(Int32).new(pull)

reader = XML::Reader.new <<-XML
<?xml version="1.0" encoding="UTF-8"?>
<XMLAttrPoint>
  <x foo="bav">1</x>
  <y>2</y>
</XMLAttrPoint>
XML

puts reader.node_type

while reader.read
  if reader.node_type.element?
    puts "#{reader.name} : #{reader.node_type}:#{reader.attributes_count} => #{reader.value}"
    p reader.expand
  end
  if reader.value
    puts "#{reader.node_type} => #{reader.value}"
  end
end
