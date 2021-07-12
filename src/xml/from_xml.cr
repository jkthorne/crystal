def Object.from_xml(string_or_io)
  new XML::Reader.new(string_or_io)
end
