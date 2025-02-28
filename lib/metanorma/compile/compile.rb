# frozen_string_literal: true

require "fileutils"
require "nokogiri"
require "htmlentities"
require "yaml"
require "fontist"
require "fontist/manifest/install"
require_relative "writeable"
require_relative "validator"
require_relative "compile_options"
require_relative "../util/fontist_helper"
require_relative "../util/util"
require_relative "extract"
require_relative "../collection/sectionsplit/sectionsplit"
require_relative "../util/worker_pool"
require_relative "output_basename"
require_relative "output_filename_config"
require_relative "flavor"
require_relative "relaton_drop"

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
    # @param filename [String] input file path
    # @param bibdata [Nokogiri::XML::Element] the bibliographic data element
    # @param options [Hash] compilation options
    # @return [Hash] paths for different output formats
    def prepare_output_paths(filename, bibdata, options)
      output_basename = OutputBasename.from_filename(
        filename,
        options[:output_dir],
        @processor,
      )

      f = File.expand_path(output_basename.semantic_xml)
      {
        xml: f,
        orig_filename: File.expand_path(filename),
        presentationxml: File.expand_path(output_basename.presentation_xml),
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

    # Generate presentation XML from semantic XML
    def generate_presentation_xml(
      source_file, semantic_xml, bibdata, output_paths, options
    )
      process_ext(
        :presentation, source_file, semantic_xml, bibdata, output_paths, options
      )
    end

    # Generate multiple output formats with parallel processing
    def generate_outputs_parallel(
      source_file, semantic_xml, bibdata, extensions, output_paths, options
    )
      @queue = ::Metanorma::Util::WorkersPool.new(
        ENV["METANORMA_PARALLEL"]&.to_i || DEFAULT_NUM_WORKERS,
      )

      # Install required fonts for all extensions
      gather_and_install_fonts(source_file, options.dup, extensions)

      # Process each extension in order
      process_extensions_in_order(
        source_file, semantic_xml, bibdata, extensions, output_paths, options
      )

      @queue.shutdown
    end

    def process_extensions_in_order(
      source_file, semantic_xml, bibdata, extensions, output_paths, options
    )
      Util.sort_extensions_execution(extensions).each do |ext|
        process_ext(
          ext, source_file, semantic_xml, bibdata, output_paths, options
        ) or break
      end
    end

    def process_input_adoc(filename, options)
      Util.log("[metanorma] Processing: AsciiDoc input.", :info)
      file = read_file(filename)
      options[:asciimath] and
        file.sub!(/^(=[^\n]+\n)/, "\\1:mn-keep-asciimath:\n")
      dir = File.dirname(filename)
      dir != "." and
        file = file.gsub(/^include::/, "include::#{dir}/")
          .gsub(/^embed::/, "embed::#{dir}/")
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

    # Export given bibliographic data to Relaton XML on disk
    # @param bibdata [Nokogiri::XML::Element] the bibliographic data element
    # @param options [Hash] compilation options
    def export_relaton_from_bibdata(bibdata, options)
      return unless options[:relaton]

      # docid = bibdata&.at("./xmlns:docidentifier")&.text || options[:filename]
      # outname = docid.sub(/^\s+/, "").sub(/\s+$/, "").gsub(/\s+/, "-") + ".xml"
      export_output(options[:relaton], bibdata.to_xml)
    end

    # @param xml [Nokogiri::XML::Document] the XML document
    # @return [Nokogiri::XML::Element] the bibliographic data element
    def extract_relaton_metadata(xml)
      xml.at("//bibdata") || xml.at("//xmlns:bibdata")
    end

    def wrap_html(options, file_extension, outfilename)
      if options[:wrapper] && /html$/.match(file_extension)
        outfilename = outfilename.sub(/\.html$/, "")
        FileUtils.mkdir_p outfilename
        FileUtils.mv "#{outfilename}.html", outfilename
        FileUtils.mv "#{outfilename}_images", outfilename, force: true
      end
    end

    # isodoc is Raw Metanorma XML

    def gather_and_install_fonts(source_file, options, extensions)
      Util.sort_extensions_execution(extensions).each do |ext|
        isodoc_options = get_isodoc_options(source_file, options, ext)
        font_install(isodoc_options.merge(options))
      end
    end

    # Process a single extension (output format)
    def process_ext(ext, source_file, semantic_xml, bibdata, output_paths,
options)
      output_basename = OutputBasename.from_filename(
        output_paths[:orig_filename],
        options[:output_dir],
        @processor,
      )
      output_paths[:ext] = @processor.output_formats[ext]
      output_paths[:out] = output_basename.for_format(ext) ||
        output_paths[:xml].sub(/\.[^.]+$/, ".#{output_paths[:ext]}")
      isodoc_options = get_isodoc_options(source_file, options, ext)

      # Handle special cases first
      return true if process_ext_special(
        ext, semantic_xml, bibdata, output_paths, options, isodoc_options
      )

      # Otherwise, determine if it uses presentation XML
      if @processor.use_presentation_xml(ext)
        # Format requires presentation XML first, then convert to final format
        process_via_presentation_xml(ext, output_paths, options, isodoc_options)
      else
        # Format can be generated directly from semantic XML
        process_from_semantic_xml(
          ext, output_paths, semantic_xml, isodoc_options
        )
      end
    end

    # Process special extensions with custom handling
    def process_ext_special(
      ext, semantic_xml, bibdata, output_paths, options, isodoc_options
    )
      if ext == :rxl

        # Special case: Relaton export
        export_relaton_from_bibdata(
          bibdata,
          options.merge(relaton: output_paths[:out]),
        )
        true

      elsif ext == :presentation && options[:passthrough_presentation_xml]

        # Special case: Pass through presentation XML
        f = if File.exist?(output_paths[:orig_filename])
              output_paths[:orig_filename]
            else
              output_paths[:xml]
            end

        FileUtils.cp f, output_paths[:presentationxml]
        true

      elsif ext == :html && options[:sectionsplit]

        # Special case: Split HTML into sections
        sectionsplit_convert(
          output_paths[:xml], semantic_xml, output_paths[:out], isodoc_options
        )
        true
      else
        false
      end
    end

    # Process format that requires presentation XML
    def process_via_presentation_xml(ext, output_paths, options, isodoc_options)
      @queue.schedule(ext, output_paths.dup, options.dup,
                      isodoc_options.dup) do |a, b, c, d|
        process_output_from_presentation_xml(a, b, c, d)
      end
    end

    # Generate output format from presentation XML
    def process_output_from_presentation_xml(ext, output_paths, options,
isodoc_options)
      @processor.output(nil, output_paths[:presentationxml],
                        output_paths[:out], ext, isodoc_options)
      wrap_html(options, output_paths[:ext], output_paths[:out])
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options[:strict] == true
      isodoc_error_process(e, strict, false)
    end

    # Process format directly from semantic XML
    def process_from_semantic_xml(ext, output_paths, semantic_xml,
isodoc_options)
      @processor.output(semantic_xml, output_paths[:xml], output_paths[:out],
                        ext, isodoc_options)
      true # Return as Thread equivalent
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options[:strict] == "true"
      isodoc_error_process(e, strict, true)
      ext != :presentation
    end

    # assume we pass in Presentation XML, but we want to recover Semantic XML
    def sectionsplit_convert(input_filename, file, output_filename = nil,
                             opts = {})
      @isodoc ||= IsoDoc::PresentationXMLConvert.new({})
      input_filename += ".xml" unless input_filename.match?(/\.xml$/)
      File.exist?(input_filename) or
        export_output(input_filename, file)
      presxml = File.read(input_filename, encoding: "utf-8")
      _xml, filename, dir = @isodoc.convert_init(presxml, input_filename, false)

      ::Metanorma::Collection::Sectionsplit.new(
        input: input_filename,
        isodoc: @isodoc,
        xml: presxml,
        base: File.basename(output_filename || filename),
        output: output_filename || filename,
        dir: dir,
        compile_opts: opts,
      ).build_collection
    end

    private

    def isodoc_error_process(err, strict, must_abort)
      if strict || err.message.include?("Fatal:")
        @errors << err.message
      else
        puts err.message
      end
      puts err.backtrace.join("\n")
      must_abort and 1
    end
  end
end
