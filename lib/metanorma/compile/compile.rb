# frozen_string_literal: true

require "digest"
require "fileutils"
require "tmpdir"
require "nokogiri"
require "htmlentities"
require "yaml"
require "fontist"
require "fontist/manifest"
require "metanorma-taste"
require "metanorma/plugin/lutaml"
require_relative "writeable"
require_relative "validator"
require_relative "compile_options"
require_relative "../util/fontist_helper"
require "metanorma-core"
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
      @retention_probe = ENV["METANORMA_RETENTION_PROBE"] == "1"
      process_options!(filename, options)
      @processor = @registry.find_processor(options[:type].to_sym)

      # Step 1: Generate Semantic XML
      semantic_result = generate_semantic_xml(filename, options) or return nil
      source_file, semantic_xml = semantic_result
      retention_probe("semantic-generated") if @retention_probe
      # All lutaml macros have expanded by the end of conversion; the
      # plugin's retained XMI graphs (LRU-bounded, gigabytes for large
      # models) are dead weight for every later phase. Flush them.
      Metanorma::Plugin::Lutaml::CacheRegistry.clear_all

      # Step 2: Prepare output paths
      xml = Nokogiri::XML(semantic_xml, &:huge)
      bibdata = extract_relaton_metadata(xml)
      # bibdata is a Node of the full-document DOM: keeping it pins the
      # whole DOM (gigabytes for large documents) for the entire output
      # phase. Re-root the fragment into its own tiny document so the
      # full DOM is collectable once this parse goes out of scope.
      bibdata = reroot_bibdata(bibdata)
      # bibdata is re-rooted and `semantic_xml` carries everything the
      # output phase needs: the full parsed DOM is dead weight from here
      # to the end of the method, and its live slots are what every GC
      # marking pass walks (#748). Drop the reference explicitly -
      # Ruby's method-scoped locals keep it alive through
      # `generate_outputs` otherwise.
      xml = nil
      retention_probe("bibdata-rerooted") if @retention_probe
      output_paths = prepare_output_paths(filename, bibdata, options)

      # Step 3: Determine which output formats to generate
      extensions = get_extensions(options)
      @extensions = extensions # Capture extensions for later access
      extensions or return nil

      # Step 4: Extract information from Semantic XML if requested
      extract_information(semantic_xml, bibdata, options)

      # Step 5: Generate output formats from Semantic XML. The output
      # converters each build their own DOMs of the semantic XML;
      # collect this phase's temporaries first so they stack on the
      # live set, not on the converter phase's high-water mark.
      GC.start
      retention_probe("pre-outputs") if @retention_probe
      init_work_root(semantic_xml, options)
      generate_outputs(
        source_file, semantic_xml, bibdata, extensions, output_paths,
        options
      )
      retention_probe("outputs-written") if @retention_probe
    ensure
      teardown_work_root(options)
      clean_exit(options)
    end

    # Stage-boundary retention probe (metanorma#748), enabled with
    # METANORMA_RETENTION_PROBE=1: one full GC, then the live slot
    # count and RSS - the numbers that tell which stage pins how much
    # of the document graph the marking passes walk.
    def retention_probe(step)
      GC.start
      rss = File.read("/proc/self/status")[/VmRSS:\s+(\d+)/, 1] rescue "?"
      warn format("[retention] %-22s live_slots=%-10d rss_kb=%s",
                  step, GC.stat[:heap_live_slots], rss)
    end

    # The work root hosts the output converters' shared asset store and
    # scratch directories for the duration of the build (isodoc#920). It
    # is keyed by the document's semantic XML, so identical documents
    # reuse the identical root and parallel documents never collide; the
    # converters derive no work paths of their own. `work_dir` overrides
    # the derivation, `keep_workdir` skips the teardown for debugging.
    def init_work_root(semantic_xml, options)
      @work_root = options[:work_dir]
      derived = @work_root.nil?
      @work_root ||= File.join(
        Dir.tmpdir, "metanorma",
        "work-#{Digest::SHA256.hexdigest(semantic_xml.to_s)}",
      )
      FileUtils.mkdir_p @work_root
      # a derived root is shared /tmp real estate like the converters'
      # scratch; a user-supplied work_dir is left with its own permissions
      FileUtils.chmod 0o777, @work_root if derived
      options[:workdir] = @work_root
      @work_root
    end

    def teardown_work_root(options)
      @work_root or return
      FileUtils.rm_rf @work_root unless options[:keep_workdir]
      @work_root = nil
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
        basename, options[:output_dir], @processor
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
          semantic_xml, options[:extract], options[:extract_type]
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
      Metanorma::TasteRegister.instance.available_tastes
        .include?(options[:supplied_type]) or return
      c = Metanorma::TasteRegister.get(options[:supplied_type])
      c.process_input_adoc_overrides(attrs, options)
    end

    def process_input_adoc_includes(file, filename, base_dir = nil)
      dir = File.dirname(filename)
      # With an explicit asset anchor (base_dir), Asciidoctor resolves
      # include targets against that anchor rather than the working
      # directory, so the docfile-directory prefix must be absolute for
      # includes to stay docfile-anchored from any working directory.
      base_dir and dir = File.expand_path(dir)
      dir != "." and
        file = file.gsub(/^include::/, "include::#{dir}/")
          .gsub(/^embed::/, "embed::#{dir}/")
      file
    end

    def process_input_adoc(filename, options)
      Util.log("[metanorma] Processing: AsciiDoc input.", :info)
      file = read_file(filename)
      file = process_input_adoc_hdr(file, options)
      file = process_input_adoc_includes(file, filename, options[:base_dir])
      update_options_after_preprocessing(file, options)
      [file, @processor.input_to_isodoc(file, filename, options)]
    end

    # need to update options, for any content added;
    # e.g. new attributes from Metanorma taste
    def update_options_after_preprocessing(file, options)
      new_options = { extension_keys: options[:extension_keys] }
      Tempfile.open(["tmp", ".adoc"], encoding: "UTF-8") do |f|
        f.write(file)
        f.close
        new_options = extract_options(f, new_options)
      end
      new_options.compact!
      new_options.delete(:filename)
      options.merge!(new_options)
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

    # Returns a mapping of format types to file suffixes based on the
    # extensions that were determined during compilation.
    # This method is only available after compile() has been called and
    # reached Step 3 where extensions are finalized.
    #
    # @return [Hash] mapping of format symbols to file extensions
    #   e.g., { html: "html", doc: "doc", pdf: "pdf" }
    # @return [Hash] empty hash if extensions haven't been captured yet
    def output_format_mapping
      @extensions && @processor or return {}
      @extensions.each_with_object({}) do |ext, mapping|
        if @processor.output_formats[ext]
          mapping[ext] = @processor.output_formats[ext]
        end
      end
    end

    def process_compile_dummy(flavor)
      file = Tempfile.new(%w(tmp .adoc))
      file.write <<~OUTPUT
        Document Title
        :flavor: #{flavor}
        :mn-output-extensions: xml, presentation

      OUTPUT
      file.close
      compile(file.path, agree_to_terms: true)
    end

    def extract_log_messages(flavor)
      process_compile_dummy(flavor)
      @log.display_messages
    end
  end
end
