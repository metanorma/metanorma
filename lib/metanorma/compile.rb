require "fileutils"
require "nokogiri"
require "htmlentities"
require "yaml"
require "fontist"
require "fontist/manifest/install"
require_relative "compile_validate"
require_relative "fontist_utils"
require_relative "util"
require_relative "sectionsplit"

module Metanorma
  class Compile
    # @return [Array<String>]
    attr_reader :errors, :processor

    def initialize
      @registry = Metanorma::Registry.instance
      @errors = []
      @isodoc = IsoDoc::Convert.new({})
      @fontist_installed = false
    end

    def compile(filename, options = {})
      require_libraries(options)
      options = options_extract(filename, options)
      validate_options(options)
      @processor = @registry.find_processor(options[:type].to_sym)
      extensions = get_extensions(options) or return nil
      (file, isodoc = process_input(filename, options)) or return nil
      relaton_export(isodoc, options)
      extract(isodoc, options[:extract], options[:extract_type])
      FontistUtils.install_fonts(@processor, options) unless @fontist_installed
      @fontist_installed = true
      process_extensions(filename, extensions, file, isodoc, options)
    end

    def require_libraries(options)
      options&.dig(:require)&.each { |r| require r }
    end

    def xml_options_extract(file)
      xml = Nokogiri::XML(file) { |config| config.huge }
      if xml.root
        @registry.root_tags.each do |k, v|
          return { type: k } if v == xml.root.name
        end
      end
      {}
    end

    def options_extract(filename, options)
      content = read_file(filename)
      o = Metanorma::Input::Asciidoc.new.extract_metanorma_options(content)
        .merge(xml_options_extract(content))
      options[:type] ||= o[:type]&.to_sym
      t = @registry.alias(options[:type]) and options[:type] = t
      dir = filename.sub(%r(/[^/]+$), "/")
      options[:relaton] ||= "#{dir}/#{o[:relaton]}" if o[:relaton]
      options[:sourcecode] ||= "#{dir}/#{o[:sourcecode]}" if o[:sourcecode]
      options[:extension_keys] ||= o[:extensions]&.split(/, */)&.map(&:to_sym)
      options[:extension_keys] = nil if options[:extension_keys] == [:all]
      options[:format] ||= :asciidoc
      options[:filename] = filename
      options
    end

    def get_extensions(options)
      options[:extension_keys] ||=
        @processor.output_formats.reduce([]) { |memo, (k, _)| memo << k }
      extensions = options[:extension_keys].reduce([]) do |memo, e|
        if @processor.output_formats[e] then memo << e
        else
          message = "[metanorma] Error: #{e} format is not supported for this standard."
          @errors << message
          Util.log(message, :error)
          memo
        end
      end
      if !extensions.include?(:presentation) && extensions.any? do |e|
        @processor.use_presentation_xml(e)
      end
        extensions << :presentation
      end
      extensions
    end

    def process_input(filename, options)
      case extname = File.extname(filename)
      when ".adoc" then process_input_adoc(filename, options)
      when ".xml" then process_input_xml(filename, options)
      else
        Util.log("[metanorma] Error: file extension #{extname} "\
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
        file.gsub!(/^include::/, "include::#{dir}/")
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

      xml = Nokogiri::XML(isodoc) { |config| config.huge }
      bibdata = xml.at("//bibdata") || xml.at("//xmlns:bibdata")
      # docid = bibdata&.at("./xmlns:docidentifier")&.text || options[:filename]
      # outname = docid.sub(/^\s+/, "").sub(/\s+$/, "").gsub(/\s+/, "-") + ".xml"
      File.open(options[:relaton], "w:UTF-8") { |f| f.write bibdata.to_xml }
    end

    def clean_sourcecode(xml)
      xml.xpath(".//callout | .//annotation | .//xmlns:callout | "\
                ".//xmlns:annotation").each(&:remove)
      xml.xpath(".//br | .//xmlns:br").each { |x| x.replace("\n") }
      HTMLEntities.new.decode(xml.children.to_xml)
    end

    def extract(isodoc, dirname, extract_types)
      return unless dirname

      if extract_types.nil? || extract_types.empty?
        extract_types = %i[sourcecode image requirement]
      end
      FileUtils.rm_rf dirname
      FileUtils.mkdir_p dirname
      xml = Nokogiri::XML(isodoc) { |config| config.huge }
      sourcecode_export(xml, dirname) if extract_types.include? :sourcecode
      image_export(xml, dirname) if extract_types.include? :image
      requirement_export(xml, dirname) if extract_types.include? :requirement
    end

    def sourcecode_export(xml, dirname)
      xml.at("//sourcecode | //xmlns:sourcecode") or return
      FileUtils.mkdir_p "#{dirname}/sourcecode"
      xml.xpath("//sourcecode | //xmlns:sourcecode").each_with_index do |s, i|
        filename = s["filename"] || sprintf("sourcecode-%04d.txt", i)
        File.open("#{dirname}/sourcecode/#{filename}", "w:UTF-8") do |f|
          f.write clean_sourcecode(s.dup)
        end
      end
    end

    def image_export(xml, dirname)
      xml.at("//image | //xmlns:image") or return
      FileUtils.mkdir_p "#{dirname}/image"
      xml.xpath("//image | //xmlns:image").each_with_index do |s, i|
        next unless /^data:image/.match? s["src"]

        %r{^data:image/(?<imgtype>[^;]+);base64,(?<imgdata>.+)$} =~ s["src"]
        filename = s["filename"] || sprintf("image-%04d.%s", i, imgtype)
        File.open("#{dirname}/image/#{filename}", "wb") do |f|
          f.write(Base64.strict_decode64(imgdata))
        end
      end
    end

    REQUIREMENT_XPATH = "//requirement | //xmlns:requirement | "\
                        "//recommendation | //xmlns:recommendation | //permission | "\
                        "//xmlns:permission".freeze

    def requirement_export(xml, dirname)
      xml.at(REQUIREMENT_XPATH) or return
      FileUtils.mkdir_p "#{dirname}/requirement"
      xml.xpath(REQUIREMENT_XPATH).each_with_index do |s, i|
        filename = s["filename"] || sprintf("%s-%04d.xml", s.name, i)
        File.open("#{dirname}/requirement/#{filename}", "w:UTF-8") do |f|
          f.write s
        end
      end
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
    def process_extensions(filename, extensions, file, isodoc, options)
      f = change_output_dir options
      xml_name = f.sub(/\.[^.]+$/, ".xml")
      presentationxml_name = f.sub(/\.[^.]+$/, ".presentation.xml")
      Util.sort_extensions_execution(extensions).each do |ext|
        file_extension = @processor.output_formats[ext]
        outfilename = f.sub(/\.[^.]+$/, ".#{file_extension}")
        isodoc_options = get_isodoc_options(file, options, ext)
        if ext == :rxl
          relaton_export(isodoc, options.merge(relaton: outfilename))
        elsif options[:passthrough_presentation_xml] && ext == :presentation
          FileUtils.cp filename, presentationxml_name
        elsif ext == :html && options[:sectionsplit]
          sectionsplit_convert(xml_name, isodoc, outfilename, isodoc_options)
        else
          if ext == :pdf && FontistUtils.has_fonts_manifest?(@processor,
                                                             options)
            isodoc_options[:mn2pdf] = {
              font_manifest: FontistUtils.location_manifest(@processor),
            }
          end
          begin
            if @processor.use_presentation_xml(ext)
              @processor.output(nil, presentationxml_name, outfilename, ext,
                                isodoc_options)
            else
              @processor.output(isodoc, xml_name, outfilename, ext,
                                isodoc_options)
            end
          rescue StandardError => e
            isodoc_error_process(e)
          end
        end
        wrap_html(options, file_extension, outfilename)
      end
    end

    private

    def isodoc_error_process(err)
      if err.message.include? "Fatal:"
        @errors << err.message
      else
        puts err.message
        puts err.backtrace.join("\n")
      end
    end

    def get_isodoc_options(file, options, ext)
      isodoc_options = @processor.extract_options(file)
      isodoc_options[:datauriimage] = true if options[:datauriimage]
      isodoc_options[:sourcefilename] = options[:filename]
      %i(bare sectionsplit no_install_fonts baseassetpath aligncrosselements)
        .each do |x|
        isodoc_options[x] ||= options[x]
      end
      isodoc_options
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
