# frozen_string_literal: true

require "fileutils"
require "nokogiri"
require "htmlentities"
require "yaml"
require "fontist"
require "fontist/manifest/install"
require "metanorma-custom-assets"
require_relative "writeable"
require_relative "validator"
require_relative "compile_options"
require_relative "../util/fontist_helper"
require_relative "../util/util"
require_relative "extract"
require_relative "../collection/sectionsplit/sectionsplit"
require_relative "../util/worker_pool"
require_relative "output_filename"
require_relative "output_filename_config"
require_relative "flavor"
require_relative "relaton_drop"
require_relative "render"

module Metanorma
  class Compile
    include Validator
    include CompileOptions
    include Flavor
    include Writeable

    DEFAULT_NUM_WORKERS = 3

    # @return [Array<String>]
    attr_reader :errors
    attr_reader :processor

    def initialize
      @registry = Metanorma::Registry.instance
      @errors = []
      @isodoc = IsoDoc::Convert.new({})
      @fontist_installed = false
      @log = Metanorma::Utils::Log.new
    end

    # Main compile method that orchestrates the document conversion process
    # @param filename [String] path to the input file
    # @param options [Hash] compilation options
    def compile(filename, options = {})
      process_options!(filename, options)
      @processor = @registry.find_processor(options[:type].to_sym)

      # Step 1: Generate Semantic XML
      semantic_result = generate_semantic_xml(filename, options)
      return nil unless semantic_result

      source_file, semantic_xml = semantic_result

      # Step 2: Prepare output paths
      xml = Nokogiri::XML(semantic_xml, &:huge)
      bibdata = extract_relaton_metadata(xml)
      output_paths = prepare_output_paths(filename, bibdata, options)

      # Step 3: Determine which output formats to generate
      extensions = get_extensions(options)
      return nil unless extensions

      # Step 4: Extract information from Semantic XML if requested
      extract_information(semantic_xml, bibdata, options)

      # Step 5: Generate output formats from Semantic XML
      generate_outputs(
        source_file,
        semantic_xml,
        bibdata,
        extensions,
        output_paths,
        options,
      )
    ensure
      clean_exit(options)
    end

    def process_options!(filename, options)
      require_libraries(options)
      options = extract_options(filename, options)
      validate_options!(options)
      @log.save_to(filename, options[:output_dir])
      options[:log] = @log
    end

    def clean_exit(options)
      options[:novalid] and return
      @log.write
    end

    # Step 1: Generate Semantic XML from input file
    # @param filename [String] input file path
    # @param options [Hash] compilation options
    # @return [Array, nil] tuple of [source_file, semantic_xml] or nil on failure
    def generate_semantic_xml(filename, options)
      case extname = File.extname(filename)
      when ".adoc" then process_input_adoc(filename, options)
      when ".xml" then process_input_xml(filename, options)
      else
        Util.log("[metanorma] Error: file extension #{extname} " \
                 "is not supported.", :error)
        nil
      end
    end

    # Step 2: Prepare output paths for generated files
    # Use default filename template if empty string is provided.
    #
    # @param filename [String] input file path
    # @param bibdata [Nokogiri::XML::Element] the bibliographic data element
    # @param options [Hash] compilation options
    # @return [Hash] paths for different output formats
    def prepare_output_paths(filename, bibdata, options)
      basename = if options[:filename_template].nil?
                   filename.sub(/\.[^.]+$/, "")
                 else
                   drop = RelatonDrop.new(bibdata)
                   config = OutputFilenameConfig.new(options[:filename_template])
                   config.generate_filename(drop)
                 end
      @output_filename = OutputFilename.new(
        basename,
        options[:output_dir],
        @processor,
      )
      {
        xml: @output_filename.semantic_xml,
        orig_filename: filename,
        presentationxml: @output_filename.presentation_xml,
      }
    end

    # Step 4: Extract information from Semantic XML
    # @param semantic_xml [String] semantic XML content
    # @param options [Hash] compilation options
    def extract_information(semantic_xml, bibdata, options)
      # Extract Relaton bibliographic data
      export_relaton_from_bibdata(bibdata, options) if options[:relaton]

      # Extract other components (sourcecode, images, requirements)
      if options[:extract]
        Extract.extract(
          semantic_xml,
          options[:extract],
          options[:extract_type],
        )
      end
    end

    # Step 5: Generate output formats from Semantic XML
    # @param source_file [String] source file content
    # @param semantic_xml [String] semantic XML content
    # @param bibdata [Nokogiri::XML::Element] the bibliographic data element
    # @param extensions [Array<Symbol>] output formats to generate
    # @param output_paths [Hash] paths for output files
    # @param options [Hash] compilation options
    def generate_outputs(
      source_file, semantic_xml, bibdata, extensions, output_paths, options
    )
      if extensions == %i(presentation)
        # Just generate presentation XML
        generate_presentation_xml(
          source_file, semantic_xml, bibdata, output_paths, options
        )
      else
        # Generate multiple output formats with parallel processing
        generate_outputs_parallel(
          source_file, semantic_xml, bibdata, extensions, output_paths, options
        )
      end
    end

    def process_input_adoc_hdr(file, options)
      hdr, rest = Metanorma::Input::Asciidoc.new.header(file)
      attrs = hdr.split("\n")
      options[:asciimath] and attrs << ":mn-keep-asciimath:"
      process_input_adoc_overrides(attrs, options)
      "#{attrs.join("\n")}\n\n#{rest}"
    end

    def process_input_adoc_overrides(attrs, options)
      c = Metanorma::CustomAssets.new(options[:supplied_type])
      c.process_input_adoc_overrides(attrs, options)
    end

    def process_input_adoc_includes(file, filename)
      dir = File.dirname(filename)
      dir != "." and
        file = file.gsub(/^include::/, "include::#{dir}/")
          .gsub(/^embed::/, "embed::#{dir}/")
      file
    end

    def process_input_adoc(filename, options)
      Util.log("[metanorma] Processing: AsciiDoc input.", :info)
      file = read_file(filename)
      file = process_input_adoc_hdr(file, options)
      file = process_input_adoc_includes(file, filename)
      [file, @processor.input_to_isodoc(file, filename, options)]
    end

    def process_input_xml(filename, _options)
      Util.log("[metanorma] Processing: Metanorma XML input.", :info)
      # TODO NN: this is a hack -- we should provide/bridge the
      # document attributes in Metanorma XML
      ["", read_file(filename)]
    end

    def read_file(filename)
      File.read(filename, encoding: "utf-8").gsub("\r\n", "\n")
    end
  end
end
