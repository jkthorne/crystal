module Spec
  # :nodoc:
  abstract class Formatter
    def initialize(@cli : CLI, @io : IO = cli.stdout)
    end

    def push(context)
    end

    def pop
    end

    def before_example(description)
    end

    def report(result)
    end

    def finish(elapsed_time, aborted)
    end

    def should_print_summary?
      false
    end

    protected def print_failure(result : Result)
      return unless ex = result.exception

      @io.puts
      @io.puts @cli.colorize("#{result.kind.to_s.upcase}: #{result.description}", result.kind)

      if ex.is_a?(SpecError)
        source_line = Spec.read_line(ex.file, ex.line)
        if source_line
          @io.puts @cli.colorize("     Failure/Error: #{source_line.strip}", :error)
        end
      end
      @io.puts

      message = ex.is_a?(SpecError) ? ex.to_s : ex.inspect_with_backtrace
      message.split('\n') do |line|
        @io.print "       "
        @io.puts @cli.colorize(line, :error)
      end

      if ex.is_a?(SpecError)
        cwd = Dir.current
        @io.puts
        @io.puts @cli.colorize("     # #{Path[ex.file].relative_to(cwd)}:#{ex.line}", :comment)
      end

      @io.puts
      @io.flush
    end
  end

  # :nodoc:
  class DotFormatter < Formatter
    @count = 0
    @split = 0

    def initialize(*args)
      super

      if split = ENV["SPEC_SPLIT_DOTS"]?
        @split = split.to_i
      end
    end

    def report(result)
      @io << @cli.colorize(result.kind.letter, result.kind)
      split_lines
      @io.flush

      if @cli.error_on_fail? && (result.kind.fail? || result.kind.error?)
        print_failure(result)
      end
    end

    private def split_lines
      return unless @split > 0
      if (@count += 1) >= @split
        @io.puts
        @count = 0
      end
    end

    def finish(elapsed_time, aborted)
      @io.puts
    end

    def should_print_summary?
      true
    end
  end

  # :nodoc:
  class VerboseFormatter < Formatter
    class Item
      def initialize(@indent : Int32, @description : String)
        @printed = false
      end

      def print(io)
        return if @printed
        @printed = true

        VerboseFormatter.print_indent(io, @indent)
        io.puts @description
      end
    end

    @indent = 0
    @last_description = ""
    @items = [] of Item

    def push(context)
      @items << Item.new(@indent, context.description)
      @indent += 1
    end

    def pop
      @items.pop
      @indent -= 1
    end

    def print_indent
      self.class.print_indent(@io, @indent)
    end

    def self.print_indent(io, indent)
      indent.times { io << "  " }
    end

    def before_example(description)
      @items.each &.print(@io)
      print_indent
      @io << description
      @last_description = description
    end

    def report(result)
      @io << '\r'
      print_indent
      @io.puts @cli.colorize(@last_description, result.kind)

      if @cli.error_on_fail? && (result.kind.fail? || result.kind.error?)
        print_failure(result)
      end
    end

    def should_print_summary?
      true
    end
  end

  # :nodoc:
  class CLI
    def formatters
      @formatters ||= [Spec::DotFormatter.new(self)] of Spec::Formatter
    end

    def override_default_formatter(formatter)
      formatters[0] = formatter
    end

    def add_formatter(formatter)
      formatters << formatter
    end
  end

  @[Deprecated("This is an internal API.")]
  def self.override_default_formatter(formatter)
    @@cli.override_default_formatter(formatter)
  end

  @[Deprecated("This is an internal API.")]
  def self.add_formatter(formatter)
    @@cli.add_formatter(formatter)
  end
end
