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
      {
        xml: "xml"
      }
    end

    def input_to_isodoc(file, filename)
      raise "This is an abstract class!"
    end

    def output(isodoc_node, outname, format, options={})
      File.open(outname, "w:UTF-8") { |f| f.write(isodoc_node) }
    end

    def extract_options(file)
      Metanorma::Input::Asciidoc.new.extract_options(file)
    end

    def extract_metanorma_options(file)
      Metanorma::Input::Asciidoc.new.extract_metanorma_options(file)
    end
  end
end
