# frozen_string_literal: true

require "liquid"
require "fileutils"

module Metanorma
  class Compile
    # Manages output paths and filenames for Metanorma document processing
    class OutputManager
      attr_reader :base_dir, :template, :metadata

      def initialize(options = {})
        @base_dir = options[:output_dir]
        @template = options[:filename_template] || default_template
        @metadata = options[:metadata] # Will be a Relaton::Liquid::Drop
      end

      # Generate paths for all outputs based on the semantic XML
      # @param input_filename [String] The input filename
      # @return [Hash] Paths for different output formats
      def prepare_output_paths(input_filename)
        base = generate_base_name(input_filename)
        f = File.expand_path(File.join(@base_dir || ".", base))

        # Ensure output directory exists
        FileUtils.mkdir_p(File.dirname(f))

        # Ensure extract directory exists
        extract_dir = File.join(@base_dir || ".", "extract")
        FileUtils.mkdir_p(extract_dir)

        {
          xml: f.sub(/\.[^.]+$/, ".xml"), # Semantic XML
          presentation: f.sub(/\.[^.]+$/, ".presentation.xml"), # Presentation XML
          html: f.sub(/\.[^.]+$/, ".html"), # HTML from Presentation XML
          pdf: f.sub(/\.[^.]+$/, ".pdf"), # PDF from Presentation XML
          doc: f.sub(/\.[^.]+$/, ".doc"), # Doc from Presentation XML
          relaton: f.sub(/\.[^.]+$/, ".relaton.xml"), # Relaton XML
          extract_dir: extract_dir, # Directory for extracted content
          orig_filename: File.expand_path(input_filename), # Original input file
        }
      end

      private

      def default_template
        "{{ id | default: basename }}"
      end

      def generate_base_name(input_filename)
        return File.basename(input_filename) unless @metadata

        # Parse template and generate name based on metadata
        template = Liquid::Template.parse(@template)
        result = template.render(@metadata.to_h)

        # Fallback to input filename if template produces empty result
        result.empty? ? File.basename(input_filename) : result
      end
    end
  end
end
