module Metanorma
  module AsciidoctorExtensions
    class GlobIncludeProcessor < ::Asciidoctor::Extensions::IncludeProcessor
      def process(_doc, reader, target_glob, attributes)
        Dir[File.join reader.dir, target_glob].sort.reverse_each do |target|
          content = File.readlines target
          content.unshift "" unless attributes["adjoin-option"]
          reader.push_include content, target, target, 1, attributes
        end
        reader
      end

      def handles?(target)
        target.include? "*"
      end
    end
  end
end

Asciidoctor::Extensions.register do
  include_processor ::Metanorma::AsciidoctorExtensions::GlobIncludeProcessor
end
