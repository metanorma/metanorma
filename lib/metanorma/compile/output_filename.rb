# frozen_string_literal: true

module Metanorma
  class Compile
    class OutputFilename
      # Returns an instance of OutputFilename from the source filename
      # @param source_filename [String] the source filename
      # @param output_dir [String, nil] the output directory
      # @param processor [Metanorma::Processor, nil] the processor
      # @return [OutputFilename] the instance of OutputFilename
      def self.from_filename(source_filename, output_dir = nil, processor = nil)
        new(strip_ext(source_filename), output_dir, processor)
      end

      class << self
        private

        def strip_ext(filename)
          filename.sub(/\.[^.]*$/, "")
        end
      end

      # @param noext_filename [String] the path (absolute/relative) of the source file, without extension (e.g., "/a/b/c/test")
      # @param output_dir [String, nil] the output directory
      # @param processor [Metanorma::Processor, nil] the processor
      # @return [OutputFilename] the instance of OutputFilename
      def initialize(noext_filename, output_dir = nil, processor = nil)
        @noext_filename = noext_filename
        @output_dir = output_dir
        @processor = processor
      end

      # Returns the full file path name with the semantic XML extension
      # @return [String] the full file path name with the semantic XML extension
      def semantic_xml
        with_extension("xml")
      end

      # Returns the full file path name with the presentation XML extension
      # @return [String] the full file path name with the presentation XML extension
      def presentation_xml
        with_extension("presentation.xml")
      end

      # Returns the full file path name with the given format extension
      # @param format [Symbol] the format
      # @return [String, nil] the full file path name with the format extension
      def for_format(format)
        ext = @processor&.output_formats&.[](format)
        ext ? with_extension(ext) : nil
      end

      # Returns the full file path name with the given extension
      # @param ext [String] the extension
      # @return [String] the full file path name with the extension
      def with_extension(ext)
        file = change_output_dir
        "#{file}.#{ext}"
      end

      private

      def change_output_dir
        File.expand_path(if !@output_dir.nil?
                           File.join(
                             @output_dir,
                             File.basename(@noext_filename),
                           )
                         else
                           @noext_filename
                         end)
      end
    end
  end
end
