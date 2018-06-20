# Registry of all Metanorma types and entry points
#

module Metanorma
  class Processor

    attr_reader :short
    attr_reader :input_format

    def initialize
      raise "This is an abstract class!"
    end

    def output_formats
      raise "This is an abstract class!"
    end

    def input_to_isodoc(file)
      raise "This is an abstract class!"
    end

    def output(isodoc_node, outname, format, options={})
      raise "This is an abstract class!"
    end

  end
end
