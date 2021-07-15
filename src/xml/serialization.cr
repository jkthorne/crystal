module XML
  annotation Element
  end

  module Serializable
    annotation Options
    end

    macro included
      # Define a `new` directly in the included type,
      # so it overloads well with other possible initializes

      def self.new(parser : ::XML::Reader)
        new_from_xml_parser(parser)
      end

      private def self.new_from_xml_parser(parser : ::XML::Reader)
        instance = allocate
        instance.initialize(__pull_for_xml_serializable: parser)
        GC.add_finalizer(instance) if instance.responds_to?(:finalize)
        instance
      end

      # When the type is inherited, carry over the `new`
      # so it can compete with other possible initializes

      macro inherited
        def self.new(parser : ::XML::Reader)
          new_from_xml_parser(parser)
        end
      end

      def initialize(*, __pull_for_xml_serializable parser : ::XML::Reader)
        {% begin %}
          {% properties = {} of Nil => Nil %}
          {% for ivar in @type.instance_vars %}
            {% ann = ivar.annotation(::XML::Field) %}
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
            parser.next
          rescue # TODO: handle errors
          end
          until parser.next
            case parser.name
              {% for name, value in properties %}
                when {{value[:key]}}
                  %found{name} = true
                end
              {% end %}
            else
              on_unknown_xml_attribute(parser)
            end
          end
        {% end %}

        after_initialize
      end

      protected def after_initialize
      end
  
      protected def on_unknown_xml_attribute(parser, key)
        parser.skip
      end
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
  end

  class SerializableError < Error
    getter klass : String
    getter attribute : String?

    def initialize(message : String?, @klass : String, @attribute : String?, line_number : Int32, column_number : Int32)
      message = String.build do |io|
        io << message
        io << "\n  parsing "
        io << klass
        if attribute = @attribute
          io << '#' << attribute
        end
      end
      super(message, line_number, column_number)
    end
  end
end
