require "spec"
require "xml"
require "../../../src/xml/pull_parser"

class XML::PullParser
  def assert(event_kind : Kind)
    kind.should eq(event_kind)
    read_next
  end

  def assert(value : Nil)
    kind.should eq(XML::PullParser::Kind::Null)
    read_next
  end

  def assert(value : Int)
    kind.should eq(XML::PullParser::Kind::Int)
    int_value.should eq(value)
    read_next
  end

  def assert(value : Float)
    kind.should eq(XML::PullParser::Kind::Float)
    float_value.should eq(value)
    read_next
  end

  def assert(value : Bool)
    kind.should eq(XML::PullParser::Kind::Bool)
    bool_value.should eq(value)
    read_next
  end

  def assert(value : String)
    kind.should eq(XML::PullParser::Kind::String)
    string_value.should eq(value)
    read_next
  end

  def assert(value : String, &)
    kind.should eq(XML::PullParser::Kind::String)
    string_value.should eq(value)
    read_next
    yield
  end

  def assert_object(&)
    kind.should eq(XML::PullParser::Kind::BeginObject)
    read_next
    yield
    kind.should eq(XML::PullParser::Kind::EndObject)
    read_next
  end

  def assert_object
    assert_object { }
  end

  def assert_error
    expect_raises XML::ParseException do
      read_next
    end
  end
end

private def assert_pull_parse(string)
  it "parses #{string}" do
    parser = XML::PullParser.new string
    parser.assert XML.parse(string).raw
    parser.kind.should eq(XML::PullParser::Kind::EOF)
  end
end

private def assert_pull_parse_error(string)
  it "errors on #{string}" do
    expect_raises XML::ParseException do
      parser = XML::PullParser.new string
      until parser.kind.eof?
        parser.read_next
      end
    end
  end
end

private def assert_raw(string, file = __FILE__, line = __LINE__)
  it "parses raw #{string.inspect}", file, line do
    pull = XML::PullParser.new(string)
    pull.read_raw.should eq(string)
  end
end

describe XML::PullParser do
  it "reads float when it is an int" do
    pull = XML::PullParser.new(%(<a>1<a>))
    f = pull.read_float
    f.should be_a(Float64)
    f.should eq(1.0)
  end
end
