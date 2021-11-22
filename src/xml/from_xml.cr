def Object.from_xml(string_or_io)
  new XML.parse(string_or_io)
end

def Union.new(node : XML::Node, type)
  {% begin %}
    case type
    {% if T.includes? Nil %}
    when Nil
      return nil
    {% end %}
    {% if T.includes? Bool %}
    when Bool
      return node.content.no_bool
    {% end %}
    {% if T.includes? String %}
    when String
      return node.content
    {% end %}
    when Int
    {% type_order = [Int64, UInt64, Int32, UInt32, Int16, UInt16, Int8, UInt8, Float64, Float32] %}
    {% for type in type_order.select { |t| T.includes? t } %}
      value = pull.read?({{type}})
      return value unless value.nil?
    {% end %}
    when .float?
    {% type_order = [Float64, Float32] %}
    {% for type in type_order.select { |t| T.includes? t } %}
      value = pull.read?({{type}})
      return value unless value.nil?
    {% end %}
    else
      # no priority type
    end
  {% end %}

  {% begin %}
    {% primitive_types = [Nil, Bool, String] + Number::Primitive.union_types %}
    {% non_primitives = T.reject { |t| primitive_types.includes? t } %}

    # If after traversing all the types we are left with just one
    # non-primitive type, we can parse it directly (no need to use `read_raw`)
    {% if non_primitives.size == 1 %}
      return {{non_primitives[0]}}.new(pull)
    {% else %}
      string = pull.read_raw
      {% for type in non_primitives %}
        begin
          return {{type}}.from_json(string)
        rescue JSON::ParseException
          # Ignore
        end
      {% end %}
      raise JSON::ParseException.new("Couldn't parse #{self} from #{string}", *location)
    {% end %}
  {% end %}
end

{% for type, method in {
                         "Int8"   => "i8",
                         "Int16"  => "i16",
                         "Int32"  => "i32",
                         "Int64"  => "i64",
                         "UInt8"  => "u8",
                         "UInt16" => "u16",
                         "UInt32" => "u32",
                         "UInt64" => "u64",
                       } %}
  def {{type.id}}.new(node : XML::Node)
    node.content.to_{{method.id}}
  end
{% end %}

def Nil.new(node : XML::Node)
  nil
end

def String.new(node : XML::Node)
  node.content
end

def Object.from_json(string_or_io, root : String)
  parser = XML::Reader.new(string_or_io)
  parser.on_key!(root) do
    new parser
  end
end
