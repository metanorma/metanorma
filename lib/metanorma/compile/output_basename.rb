# frozen_string_literal: true

module Metanorma
  class Compile
    class OutputBasename
      # Returns an instance of OutputBasename from the source filename
      # @param source_filename [String] the source filename
      # @param output_dir [String, nil] the output directory
      # @param processor [Metanorma::Processor, nil] the processor
      # @return [OutputBasename] the instance of OutputBasename
      def self.from_filename(source_filename, output_dir = nil, processor = nil)
        new(strip_ext(source_filename), output_dir, processor)
      end

      class << self
        private

        def strip_ext(basename)
          basename.sub(/\.[^.]*$/, "")
        end
      end

      # @param noext_filename [String] the path (absolute/relative) of the source file, without extension (e.g., "/a/b/c/test")
      # @param output_dir [String, nil] the output directory
      # @param processor [Metanorma::Processor, nil] the processor
      # @return [OutputBasename] the instance of OutputBasename
      def initialize(noext_filename, output_dir = nil, processor = nil)
        @noext_filename = noext_filename
        @output_dir = output_dir
        @processor = processor
      end

      # Returns the basename with the semantic XML extension
      # @return [String] the basename with the semantic XML extension
      def semantic_xml
        with_extension("xml")
      end

      # Returns the basename with the presentation XML extension
      # @return [String] the basename with the presentation XML extension
      def presentation_xml
        with_extension("presentation.xml")
      end

      # Returns the basename with the given format extension
      # @param format [Symbol] the format
      # @return [String, nil] the basename with the format extension
      def for_format(format)
        ext = @processor&.output_formats&.[](format)
        ext ? with_extension(ext) : nil
      end

      # Returns the basename with the given extension
      # @param ext [String] the extension
      # @return [String] the basename with the extension
      def with_extension(ext)
        base = change_output_dir
        "#{base}.#{ext}"
      end

      private

      def change_output_dir
        if @output_dir
          File.join(@output_dir, File.basename(@noext_filename))
        else
          @noext_filename
        end
      end
    end
  end
end
