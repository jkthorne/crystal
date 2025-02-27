# This script generates the file spec/std/string/graphemes_break_spec.cr
# that contains test cases for Unicode grapheme clusters based on the default
# Grapheme_Cluster_Break Test

# http://www.unicode.org/Public/x.y.z/ucd/auxiliary/GraphemeBreakTest.txt

require "http/client"
require "../src/compiler/crystal/formatter"

UCD_ROOT = "http://www.unicode.org/Public/#{Unicode::VERSION}/ucd/"

url = "#{UCD_ROOT}auxiliary/GraphemeBreakTest.txt"

path = "#{__DIR__}/../spec/std/string/grapheme_break_spec.cr"

def string_or_char(string)
  if string.size == 1
    string[0]
  else
    string
  end
end

File.open(path, "w") do |file|
  file.puts <<-CR
    # This file was automatically generated by running:
    #
    #   scripts/generate_grapheme_break_spec.cr
    #
    # See https://www.unicode.org/license.html for the Unicode license agreement.
    # DO NOT EDIT

    require "./spec_helper"

    describe "String#each_grapheme" do
    CR
  HTTP::Client.get(url).body.each_line do |line|
    next if line.starts_with?('#')

    format, _, comment = line.partition('#')

    graphemes = [] of String | Char
    string = String.build do |io|
      grapheme = String::Builder.new
      format.split.in_groups_of(2) do |ary|
        operator, codepoint = ary
        break if codepoint.nil?
        char = codepoint.to_i(16).chr
        io << char
        case operator
        when "÷"
          unless grapheme.empty?
            graphemes << string_or_char(grapheme.to_s)
          end
          grapheme = String::Builder.new
        when "×"
        else raise "unexpected operator #{operator.inspect}"
        end
        grapheme << char
      end
      graphemes << string_or_char(grapheme.to_s)
    end

    file.puts "  it_iterates_graphemes #{string.dump}, [#{graphemes.join(", ", &.dump)}] # #{comment}"
  end
  file.puts "end"
end

`crystal tool format #{path}`
