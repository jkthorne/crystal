def Object.from_xml(string_or_io)
  new XML.parse(string_or_io)
end

def Union.new(node : XML::Node)
  {% begin %}
    case content = node.content
    {% if T.includes? Nil %}
    when .blank?
      return nil
    {% end %}
    {% if T.includes? Bool %}
    when .includes?(%w(true false))
      if content == "true"
        return true
      elsif content = "false"
        return false
      else
        raise XML::SerializableError.new("failed to parse bool", Bool, nil, Int32::MIN)
      end
    {% end %}
    {%
      numeral_methods = {
        Int64   => "i64",
        UInt64  => "u64",
        Int32   => "i32",
        UInt32  => "u32",
        Int16   => "i16",
        UInt16  => "u16",
        Int8    => "i8",
        UInt8   => "u8",
        Float64 => "f64",
        Float32 => "f32",
      }
    %}
    {% type_order = [Int64, UInt64, Int32, UInt32, Int16, UInt16, Int8, UInt8, Float64, Float32] %}
    {% for type in type_order.select { |t| T.includes? t } %}
      when .to_{{numeral_methods[type].id}}?
        return content.not_nil!.to_{{numeral_methods[type].id}}
    {% end %}
    {% if T.includes? String %}
    else
      return node.content
    {% else %}
    else
      # no priority type
    {% end %}
    end
  {% end %}

  {% begin %}
    {% primitive_types = [Nil, Bool, String] + Number::Primitive.union_types %}
    {% non_primitives = T.reject { |t| primitive_types.includes? t } %}

    # If after traversing all the types we are left with just one
    # non-primitive type, we can parse it directly (no need to use `read_raw`)
    {% if non_primitives.size == 1 %}
      return {{non_primitives[0]}}.new(node)
    {% else %}
      string = node.content
      {% for type in non_primitives %}
        begin
          return {{type}}.from_json(string)
        rescue XML::Error
          # Ignore
        end
      {% end %}
      raise XML::Error.new("Couldn't parse #{self} from #{string}", Int32::MIN)
    {% end %}
  {% end %}
end

def Nil.new(node : XML::Node)
  nil
end

# {% for type, method in {
#                          "Int8"   => "i8",
#                          "Int16"  => "i16",
#                          "Int32"  => "i32",
#                          "Int64"  => "i64",
#                          "UInt8"  => "u8",
#                          "UInt16" => "u16",
#                          "UInt32" => "u32",
#                          "UInt64" => "u64",
#                        } %}
#   def {{type.id}}.new(node : XML::Node)
#     begin
#       value.to_{{method.id}}
#     rescue ex : OverflowError | ArgumentError
#       raise XML::ParseException.new("Can't read {{type.id}}", nil, ex)
#     end
#   end

#   def {{type.id}}.from_json_object_key?(key : String)
#     key.to_{{method.id}}?
#   end
# {% end %}

# TODO(jack): testing parsing
def Nil.new(node : XML::Node)
  nil
end

def Int32.new(node : XML::Node)
  1
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
