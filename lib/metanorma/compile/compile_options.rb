require "csv"

module Metanorma
  class Compile
    def require_libraries(options)
      options&.dig(:require)&.each { |r| require r }
    end

    def xml_options_extract(file)
      xml = Nokogiri::XML(file, &:huge)
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
      options[:relaton] ||= File.join(dir, o[:relaton]) if o[:relaton]
      options[:sourcecode] ||= File.join(dir, o[:sourcecode]) if o[:sourcecode]
      options[:extension_keys] ||= o[:extensions]&.split(/, */)&.map(&:to_sym)
      options[:extension_keys] = nil if options[:extension_keys] == [:all]
      options[:format] ||= :asciidoc
      options[:filename] = filename
      options[:fontlicenseagreement] ||= "no-install-fonts"
      options[:novalid] = o[:novalid] if o[:novalid]
      options
    end

    def get_extensions(options)
      ext = extract_extensions(options)
      !ext.include?(:presentation) && ext.any? do |e|
        @processor.use_presentation_xml(e)
      end and ext << :presentation
      !ext.include?(:rxl) && options[:site_generate] and
        ext << :rxl
      ext
    end

    def extract_extensions(options)
      options[:extension_keys] ||=
        @processor.output_formats.reduce([]) { |memo, (k, _)| memo << k }
      options[:extension_keys].reduce([]) do |memo, e|
        if @processor.output_formats[e] then memo << e
        else
          unsupported_format_error(e)
          memo
        end
      end
    end

    def font_install(opt)
      @fontist_installed or
        Util::FontistHelper.install_fonts(@processor, opt)
      @fontist_installed = true
    end

    private

    def unsupported_format_error(ext)
      message = "[metanorma] Error: #{ext} format is not supported " \
                "for this standard."
      @errors << message
      Util.log(message, :error)
    end

    def get_isodoc_options(file, options, ext)
      ret = @processor.extract_options(file)
      dir = options[:filename].sub(%r(/[^/]+$), "/")
      ret[:i18nyaml] &&= File.join(dir, ret[:i18nyaml])
      copy_isodoc_options_attrs(options, ret)
      font_manifest_mn2pdf(options, ret, ext)
      ret[:output_formats]&.select! do |k, _|
        options[:extension_keys].include?(k)
      end
      ret[:log] = @log
      ret
    end

    def copy_isodoc_options_attrs(options, ret)
      ret[:datauriimage] = true if options[:datauriimage]
      ret[:sourcefilename] = options[:filename]
      %i(bare sectionsplit install_fonts baseassetpath aligncrosselements
         tocfigures toctables tocrecommendations strict)
        .each { |x| ret[x] ||= options[x] }
    end

    def font_manifest_mn2pdf(options, ret, ext)
      custom_fonts = Util::FontistHelper
        .has_custom_fonts?(@processor, options, ret)

      ext == :pdf && custom_fonts and
        ret[:mn2pdf] = {
          font_manifest: Util::FontistHelper.location_manifest(@processor, ret),
        }
    end
  end
end
