require "fileutils"
require "nokogiri"
require "htmlentities"
require "yaml"
require "fontist"
require "fontist/manifest/install"
require_relative "compile_validate"
require_relative "compile_options"
require_relative "../util/fontist_helper"
require_relative "../util/util"
require_relative "extract"
require_relative "../collection/sectionsplit/sectionsplit"
require_relative "../util/worker_pool"

module Metanorma
  class Compile
    # @return [Array<String>]
    attr_reader :errors, :processor

    def initialize
      @registry = Metanorma::Registry.instance
      @errors = []
      @isodoc = IsoDoc::Convert.new({})
      @fontist_installed = false
      @log = Metanorma::Utils::Log.new
    end

    def compile(filename, options = {})
      options_process(filename, options)
      @processor = @registry.find_processor(options[:type].to_sym)
      (file, isodoc = process_input(filename, options)) or return nil
      extensions = get_extensions(options) or return nil
      relaton_export(isodoc, options)
      extract(isodoc, options[:extract], options[:extract_type])
      process_exts(filename, extensions, file, isodoc, options)
      clean_exit(options)
    end

    def options_process(filename, options)
      require_libraries(options)
      options = options_extract(filename, options)
      validate_options(options)
      @log.save_to(filename, options[:output_dir])
      options[:log] = @log
    end

    def clean_exit(options)
      options[:novalid] and return
      @log.write
    end

    def process_input(filename, options)
      case extname = File.extname(filename)
      when ".adoc" then process_input_adoc(filename, options)
      when ".xml" then process_input_xml(filename, options)
      else
        Util.log("[metanorma] Error: file extension #{extname} " \
                 "is not supported.", :error)
        nil
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

    def relaton_export(isodoc, options)
      return unless options[:relaton]

      xml = Nokogiri::XML(isodoc, &:huge)
      bibdata = xml.at("//bibdata") || xml.at("//xmlns:bibdata")
      # docid = bibdata&.at("./xmlns:docidentifier")&.text || options[:filename]
      # outname = docid.sub(/^\s+/, "").sub(/\s+$/, "").gsub(/\s+/, "-") + ".xml"
      File.open(options[:relaton], "w:UTF-8") { |f| f.write bibdata.to_xml }
    end

    def export_output(fname, content, **options)
      mode = options[:binary] ? "wb" : "w:UTF-8"
      File.open(fname, mode) { |f| f.write content }
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
    def process_exts(filename, extensions, file, isodoc, options)
      f = File.expand_path(change_output_dir(options))
      fnames = { xml: f.sub(/\.[^.]+$/, ".xml"), f: f,
                 orig_filename: File.expand_path(filename),
                 presentationxml: f.sub(/\.[^.]+$/, ".presentation.xml") }
      @queue = ::Metanorma::Util::WorkersPool
        .new(ENV["METANORMA_PARALLEL"]&.to_i || 3)
      gather_and_install_fonts(file, options.dup, extensions)
      process_exts_run(fnames, file, isodoc, extensions, options)
      @queue.shutdown
    end

    def process_exts_run(fnames, file, isodoc, extensions, options)
      Util.sort_extensions_execution(extensions).each do |ext|
        process_ext(ext, file, isodoc, fnames, options) or break
      end
    end

    def gather_and_install_fonts(file, options, extensions)
      Util.sort_extensions_execution(extensions).each do |ext|
        isodoc_options = get_isodoc_options(file, options, ext)
        font_install(isodoc_options.merge(options))
      end
    end

    def process_ext(ext, file, isodoc, fnames, options)
      fnames[:ext] = @processor.output_formats[ext]
      fnames[:out] = fnames[:f].sub(/\.[^.]+$/, ".#{fnames[:ext]}")
      isodoc_options = get_isodoc_options(file, options, ext)
      thread = true
      unless process_ext_simple(ext, isodoc, fnames, options,
                                isodoc_options)
        thread = process_exts1(ext, fnames, isodoc, options, isodoc_options)
      end
      thread
    end

    def process_ext_simple(ext, isodoc, fnames, options, isodoc_options)
      if ext == :rxl
        relaton_export(isodoc, options.merge(relaton: fnames[:out]))
      elsif options[:passthrough_presentation_xml] && ext == :presentation
        #f = File.exist?(fnames[:f]) ? fnames[:f] : fnames[:orig_filename]
        f = File.exist?(fnames[:orig_filename]) ? fnames[:orig_filename] : fnames[:f]
        FileUtils.cp f, fnames[:presentationxml]
      elsif ext == :html && options[:sectionsplit]
        sectionsplit_convert(fnames[:xml], isodoc, fnames[:out],
                             isodoc_options)
      else return false
      end
      true
    end

    def process_exts1(ext, fnames, isodoc, options, isodoc_options)
      if @processor.use_presentation_xml(ext)
        @queue.schedule(ext, fnames.dup, options.dup,
                        isodoc_options.dup) do |a, b, c, d|
          process_output_threaded(a, b, c, d)
        end
      else
        process_output_unthreaded(ext, fnames, isodoc, isodoc_options)
      end
    end

    def process_output_threaded(ext, fnames1, options1, isodoc_options1)
      @processor.output(nil, fnames1[:presentationxml], fnames1[:out], ext,
                        isodoc_options1)
      wrap_html(options1, fnames1[:ext], fnames1[:out])
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options1[:strict] == true
      isodoc_error_process(e, strict, false)
    end

    def process_output_unthreaded(ext, fnames, isodoc, isodoc_options)
      @processor.output(isodoc, fnames[:xml], fnames[:out], ext,
                        isodoc_options)
      true # return as Thread
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
        File.open(input_filename, "w:UTF-8") { |f| f.write(file) }
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

    # @param options [Hash]
    # @return [String]
    def change_output_dir(options)
      if options[:output_dir]
        File.join options[:output_dir], File.basename(options[:filename])
      else options[:filename]
      end
    end
  end
end
