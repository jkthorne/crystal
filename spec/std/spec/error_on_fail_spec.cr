require "spec"

private def build_report(error_on_fail = false, &)
  String.build do |io|
    cli = Spec::CLI.new(io)
    cli.@error_on_fail = error_on_fail
    formatter = Spec::DotFormatter.new(cli)
    yield formatter
    formatter.finish(Time::Span.zero, false)
  end
end

private def exception_with_backtrace(msg)
  raise Spec::AssertionFailed.new(msg, __FILE__, __LINE__)
rescue e
  e
end

describe "--error-on-fail flag" do
  it "does not print errors immediately by default" do
    output = build_report(false) do |f|
      f.report Spec::Result.new(:success, "should pass", "spec/some_spec.cr", 10, nil, nil)
      f.report Spec::Result.new(:fail, "should fail", "spec/some_spec.cr", 20, nil, exception_with_backtrace("Expected true"))
      f.report Spec::Result.new(:success, "should pass again", "spec/some_spec.cr", 30, nil, nil)
    end

    # Without the flag, only dots should be printed
    output.should contain(".")
    output.should contain("F")
    output.should_not contain("FAIL:")
    output.should_not contain("Expected true")
  end

  it "prints errors immediately when --error-on-fail is set" do
    output = build_report(true) do |f|
      f.report Spec::Result.new(:success, "should pass", "spec/some_spec.cr", 10, nil, nil)
      f.report Spec::Result.new(:fail, "should fail", "spec/some_spec.cr", 20, nil, exception_with_backtrace("Expected true"))
    end

    # With the flag, dots AND error details should be printed
    output.should contain(".")
    output.should contain("F")
    output.should contain("FAIL:")
    output.should contain("should fail")
    output.should contain("Expected true")
  end

  it "prints errors for both failures and errors" do
    output = build_report(true) do |f|
      f.report Spec::Result.new(:error, "should error", "spec/some_spec.cr", 20, nil, exception_with_backtrace("Runtime error"))
    end

    output.should contain("E")
    output.should contain("ERROR:")
    output.should contain("should error")
    output.should contain("Runtime error")
  end

  it "does not print for pending or successful tests" do
    output = build_report(true) do |f|
      f.report Spec::Result.new(:success, "should pass", "spec/some_spec.cr", 10, nil, nil)
      f.report Spec::Result.new(:pending, "should be pending", "spec/some_spec.cr", 20, nil, nil)
    end

    output.should contain(".")
    output.should contain("*")
    output.should_not contain("SUCCESS:")
    output.should_not contain("PENDING:")
  end
end
