require "fileutils"
require "nokogiri"
require "htmlentities"

module Metanorma
  class Compile
    def initialize
      @registry = Metanorma::Registry.instance
    end

    def compile(filename, options = {})
      options = options_extract(filename, options)
      validate(options) or return nil
      require_libraries(options)
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

    def options_extract(filename, options)
      o = Metanorma::Input::Asciidoc.new.extract_metanorma_options(File.read(filename, encoding: "utf-8"))
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
        puts "[metanorma] Error: Please specify a standard type: #{@registry.supported_backends}."
        return nil
      end
      stdtype = options[:type].to_sym
      unless @registry.supported_backends.include? stdtype
        puts "[metanorma] Warning: #{stdtype} is not a default standard type."
        puts "[metanorma] Info: Attempting to load `metanorma-#{stdtype}` gem for standard type `#{stdtype}`."
      end
      begin
        require "metanorma-#{stdtype}"
        puts "[metanorma] Info: gem `metanorma-#{stdtype}` loaded."
      rescue LoadError
        puts "[metanorma] Error: loading gem `metanorma-#{stdtype}` failed. Exiting."
        return false
      end
      unless @registry.supported_backends.include? stdtype
        puts "[metanorma] Error: The `metanorma-#{stdtype}` gem still doesn't support `#{stdtype}`. Exiting."
        return false
      end
      true
    end

    def validate_format(options)
      unless options[:format] == :asciidoc
        puts "[metanorma] Error: Only source file format currently supported is 'asciidoc'."
        return false
      end
      true
    end

    def get_extensions(options)
      options[:extension_keys] ||= @processor.output_formats.inject([]) do |memo, (k, _)|
        memo << k; memo
      end
      extensions = options[:extension_keys].inject([]) do |memo, e|
        @processor.output_formats[e] and memo << e or
          puts "[metanorma] Error: #{e} format is not supported for this standard."
        memo
      end
      extensions
    end

    def process_input(filename, options)
      case extname = File.extname(filename)
      when ".adoc"
        puts "[metanorma] Processing: Asciidoctor input."
        file = File.read(filename, encoding: "utf-8")
        if options[:asciimath]
          file.sub!(/^(=[^\n]+\n)/, "\\1:mn-keep-asciimath:\n")
        end
        [file, @processor.input_to_isodoc(file, filename)]
      when ".xml"
        puts "[metanorma] Processing: Metanorma XML input."
        # TODO NN: this is a hack -- we should provide/bridge the
        # document attributes in Metanorma XML
        ["", File.read(filename, encoding: "utf-8")]
      else
        puts "[metanorma] Error: file extension #{extname} is not supported."
        nil
      end
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
          @processor.output(isodoc, outfilename, ext, isodoc_options)
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
