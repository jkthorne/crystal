require "benchmark"

class Array(T)
  def bubble_sort
  end
end

Benchmark.ips do |x|
  x.report("eiusmod") { LOREM.byte_index("eiusmod") }
  x.report("consequat") { LOREM.byte_index("consequat") }
  x.report("fugiat") { LOREM.byte_index("fugiat") }
  x.report("yolo") { LOREM.byte_index("yolo") }
end
