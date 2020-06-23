require "fileutils"
require "nokogiri"
require "htmlentities"

module Metanorma
  class Compile
    # @return [Array<String>]
    attr_reader :errors

    def initialize
      @registry = Metanorma::Registry.instance
      @errors = []
    end

    def compile(filename, options = {})
      require_libraries(options)
      options = options_extract(filename, options)
      validate(options) or return nil
      @processor = @registry.find_processor(options[:type].to_sym)
      extensions = get_extensions(options) or return nil
      (file, isodoc = process_input(filename, options)) or return nil
      relaton_export(isodoc, options)
      extract(isodoc, options[:extract], options[:extract_type])
      process_extensions(extensions, file, isodoc, options)
    end

    def require_libraries(options)
      if options[:require]
        options[:require].each do |r|
          require r
        end
      end
    end

    def xml_options_extract(file)
      xml = Nokogiri::XML(file)
      if xml.root
        @registry.root_tags.each do |k, v|
          return { type: k }  if v == xml.root.name
        end
      end
      {}
    end

    def options_extract(filename, options)
      content = read_file(filename)
      o = Metanorma::Input::Asciidoc.new.extract_metanorma_options(content)
      o = o.merge(xml_options_extract(content))
      options[:type] ||= o[:type]&.to_sym
      dir = filename.sub(%r(/[^/]+$), "/")
      options[:relaton] ||= "#{dir}/#{o[:relaton]}" if o[:relaton]
      options[:sourcecode] ||= "#{dir}/#{o[:sourcecode]}" if o[:sourcecode]
      options[:extension_keys] ||= o[:extensions]&.split(/,[ ]*/)&.map(&:to_sym)
      options[:extension_keys] = nil if options[:extension_keys] == [:all]
      options[:format] ||= :asciidoc
      options[:filename] = filename
      options
    end

    def validate(options)
      validate_type(options) && validate_format(options)
    end

    def validate_type(options)
      unless options[:type]
        Util.log("[metanorma] Error: Please specify a standard type: #{@registry.supported_backends}.", :error)
        return nil
      end
      stdtype = options[:type].to_sym
      unless @registry.supported_backends.include? stdtype
        Util.log("[metanorma] Info: Loading `metanorma-#{stdtype}` gem for standard type `#{stdtype}`.", :info)
      end
      begin
        require "metanorma-#{stdtype}"
        Util.log("[metanorma] Info: gem `metanorma-#{stdtype}` loaded.", :info)
      rescue LoadError
        Util.log("[metanorma] Error: loading gem `metanorma-#{stdtype}` failed. Exiting.", :error)
        return false
      end
      unless @registry.supported_backends.include? stdtype
        Util.log("[metanorma] Error: The `metanorma-#{stdtype}` gem still doesn't support `#{stdtype}`. Exiting.", :error)
        return false
      end
      true
    end

    def validate_format(options)
      unless options[:format] == :asciidoc
        Util.log("[metanorma] Error: Only source file format currently supported is 'asciidoc'.", :error)
        return false
      end
      true
    end

    def get_extensions(options)
      options[:extension_keys] ||= @processor.output_formats.reduce([]) do |memo, (k, _)|
        memo << k
      end
      extensions = options[:extension_keys].reduce([]) do |memo, e|
        if @processor.output_formats[e]
          memo << e
        else
          message = "[metanorma] Error: #{e} format is not supported for this standard."
          @errors << message
          Util.log(message, :error)
          memo
        end
      end
      extensions
    end

    def process_input(filename, options)
      case extname = File.extname(filename)
      when ".adoc"
        Util.log("[metanorma] Processing: AsciiDoc input.", :info)
        file = read_file(filename)
        options[:asciimath] and
          file.sub!(/^(=[^\n]+\n)/, "\\1:mn-keep-asciimath:\n")
        dir = File.dirname(filename)
        dir != '.' and
          file.gsub!(/^include::/, "include::#{dir}/")
        [file, @processor.input_to_isodoc(file, filename)]
      when ".xml"
        Util.log("[metanorma] Processing: Metanorma XML input.", :info)
        # TODO NN: this is a hack -- we should provide/bridge the
        # document attributes in Metanorma XML
        ["", read_file(filename)]
      else
        Util.log("[metanorma] Error: file extension #{extname} is not supported.", :error)
        nil
      end
    end

    def read_file(filename)
      File.read(filename, encoding: "utf-8").gsub("\r\n", "\n")
    end

    def relaton_export(isodoc, options)
      return unless options[:relaton]
      xml = Nokogiri::XML(isodoc)
      bibdata = xml.at("//bibdata") || xml.at("//xmlns:bibdata")
      #docid = bibdata&.at("./xmlns:docidentifier")&.text || options[:filename]
      #outname = docid.sub(/^\s+/, "").sub(/\s+$/, "").gsub(/\s+/, "-") + ".xml"
      File.open(options[:relaton], "w:UTF-8") { |f| f.write bibdata.to_xml }
    end

    def clean_sourcecode(xml)
      xml.xpath(".//callout | .//annotation | .//xmlns:callout | .//xmlns:annotation").each do |x|
        x.remove
      end
      xml.xpath(".//br | .//xmlns:br").each { |x| x.replace("\n") }
      HTMLEntities.new.decode(xml.children.to_xml)
    end

    def extract(isodoc, dirname, extract_types)
      return unless dirname
      if extract_types.nil? || extract_types.empty?
        extract_types = [:sourcecode, :image, :requirement]
      end
      FileUtils.rm_rf dirname
      FileUtils.mkdir_p dirname
      xml = Nokogiri::XML(isodoc)
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
        next unless /^data:image/.match s["src"]
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

    def process_extensions(extensions, file, isodoc, options)
      extensions.each do |ext|
        isodoc_options = @processor.extract_options(file)
        isodoc_options[:datauriimage] = true if options[:datauriimage]
        file_extension = @processor.output_formats[ext]
        outfilename = options[:filename].sub(/\.[^.]+$/, ".#{file_extension}")
        if ext == :rxl
          options[:relaton] = outfilename
          relaton_export(isodoc, options)
        else
          begin
          @processor.output(isodoc, outfilename, ext, isodoc_options)
          rescue StandardError => e  
            puts e.message
          end
        end
        if options[:wrapper] and /html$/.match file_extension
          outfilename = outfilename.sub(/\.html$/, "")
          FileUtils.mkdir_p outfilename
          FileUtils.mv "#{outfilename}.html", outfilename
          FileUtils.mv "#{outfilename}_images", outfilename, force: true
        end
      end
    end
  end
end
