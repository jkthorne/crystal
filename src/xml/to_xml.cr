class Hash
  # Serializes this Hash into JSON.
  #
  # Keys are serialized by invoking `to_json_object_key` on them.
  # Values are serialized with the usual `to_json(json : JSON::Builder)`
  # method.
  def to_xml(name : String, xml : XML::Builder) : Nil
    xml.element(name) do
      each do |key, value|
        xml.element(key) do
          value.to_xml(value, xml)
        end
      end
    end
  end
end
