module XML
  struct Any
    alias Type = Nil | Bool | Int64 | Float64 | String | Array(Any) | Hash(String, Any)

    # Returns the raw underlying value.
    getter raw : Type

    # Creates a `XML::Any` that wraps the given value.
    def initialize(@raw : Type)
    end
  end

  annotation Element
  end

  module Serializable
    annotation Options
    end

    macro included
      def self.new(node : ::XML::Node)
        new_from_xml_node(node)
      end

      private def self.new_from_xml_node(node : ::XML::Node)
        instance = allocate
        instance.initialize(__for_xml_serializable: node)
        GC.add_finalizer(instance) if instance.responds_to?(:finalize)
        instance
      end

      macro inherited
        def self.new(node : ::XML::Node)
          new_from_xml_node(node)
        end
      end
    end

    def initialize(*, __for_xml_serializable node : ::XML::Node)
      {% begin %}
        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(::XML::Element) %}
          {% unless ann && (ann[:ignore] || ann[:ignore_deserialize]) %}
            {%
              properties[ivar.id] = {
                type: ivar.type,
                key:  ((ann && ann[:key]) || ivar).id.stringify,
              }
            %}
          {% end %}

          {% for name, value in properties %}
            %var{name} = nil
            %found{name} = false
          {% end %}

          begin
            node.next
          rescue exc : ::XML::Error
            raise ::XML::SerializableError.new(exc.message, self.class.to_s, nil, exc.line_number)
          end

          until node.next
            case node.name
                {% for name, value in properties %}
                when {{value[:key]}}
                  %found{name} = true
                {% end %}
            else
              on_unknown_xml_attribute(node, node.name)
            end
          end
        {% end %}
      {% end %}

      after_initialize
    end

    protected def after_initialize
    end

    protected def on_unknown_xml_attribute(node, key)
    end

    def to_xml
      XML.build do |xml|
        {% begin %}
          {% properties = {} of Nil => Nil %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(::XML::Element) %}
            {% unless ann && (ann[:ignore] || ann[:ignore_serialize]) %}
              {%
                properties[ivar.id] = {
                  type: ivar.type,
                  key:  ((ann && ann[:key]) || ivar).id.stringify,
                }
              %}
            {% end %}
          {% end %}

          xml.element({{@type.name.stringify}}) do
            {% for name, value in properties %}
              _{{name}} = @{{name}}

              if _{{name}}
                xml.element({{value[:key]}}) { xml.text _{{name}}.to_s }
              else
                xml.element({{value[:key]}})
              end
            {% end %}
          end
        {% end %}
      end
    end

    module Unmapped
      # TODO: use alias other then JSON::Any
      @[XML::Element(ignore: true)]
      property xml_unmapped = Hash(String, XML::Any).new

      protected def on_unknown_xml_attribute(node, name)
        xml_unmapped[name] = begin
          XML::Any.new(node.content)
        end
      end
    end
  end

  class SerializableError < XML::Error
    getter klass : String
    getter attribute : String?

    def initialize(message : String?, @klass : String, @attribute : String?, line_number : Int32)
      message = String.build do |io|
        io << message
        io << "\n  parsing "
        io << klass
        if attribute = @attribute
          io << '#' << attribute
        end
      end
      super(message, line_number)
    end
  end
end
