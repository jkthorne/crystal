def Object.from_xml(string_or_io)
  new XML::Reader.new(string_or_io)
end

def Object.from_json(string_or_io, root : String)
  parser = XML::Reader.new(string_or_io)
  parser.on_key!(root) do
    new parser
  end
end
