# frozen_string_literal: true

module Metanorma
  class Compile
    class OutputFilename
      # @param source_filename [String] the source filename (e.g., "test.adoc")
      # @param output_dir [String, nil] the output directory
      # @param processor [Metanorma::Processor, nil] the processor
      # @return [String] the filename with the extension
      def initialize(source_filename, output_dir = nil, processor = nil)
        @source_filename = source_filename
        @output_dir = output_dir
        @processor = processor
      end

      # Returns the filename with the semantic XML extension
      # @return [String] the filename with the semantic XML extension
      def semantic_xml
        with_extension("xml")
      end

      # Returns the filename with the presentation XML extension
      # @return [String] the filename with the presentation XML extension
      def presentation_xml
        with_extension("presentation.xml")
      end

      # Returns the filename with the given format extension
      # @param format [Symbol] the format
      # @return [String, nil] the filename with the format extension
      def for_format(format)
        ext = @processor&.output_formats&.[](format)
        ext ? with_extension(ext) : nil
      end

      # Returns the filename with the given extension
      # @param ext [String] the extension
      # @return [String] the filename with the extension
      def with_extension(ext)
        base = change_output_dir
        base.sub(/\.[^.]+$/, ".#{ext}")
      end

      private

      def change_output_dir
        if @output_dir
          File.join(@output_dir, File.basename(@source_filename))
        else
          @source_filename
        end
      end
    end
  end
end
