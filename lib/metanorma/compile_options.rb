require "csv"

module Metanorma
  class Compile
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
      options[:relaton] ||= File.join(dir, o[:relaton]) if o[:relaton]
      options[:sourcecode] ||= File.join(dir, o[:sourcecode]) if o[:sourcecode]
      options[:extension_keys] ||= o[:extensions]&.split(/, */)&.map(&:to_sym)
      options[:extension_keys] = nil if options[:extension_keys] == [:all]
      options[:format] ||= :asciidoc
      options[:filename] = filename
      options[:fontlicenseagreement] ||= "no-install-fonts"
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

    def font_install(opt)
      FontistUtils.install_fonts(@processor, opt) unless @fontist_installed
      @fontist_installed = true
      return if !opt[:fonts] ||
        opt[:fontlicenseagreement] == "continue-without-fonts"

      confirm = opt[:fontlicenseagreement] == "no-install-fonts" ? "no" : "yes"
      CSV.parse_line(opt[:fonts], col_sep: ";").map(&:strip).each do |f|
        Fontist::Font.install(f, confirmation: confirm)
      end
    end

    private

    def get_isodoc_options(file, options, ext)
      ret = @processor.extract_options(file)
      ret[:datauriimage] = true if options[:datauriimage]
      ret[:sourcefilename] = options[:filename]
      %i(bare sectionsplit no_install_fonts baseassetpath aligncrosselements
         tocfigures toctables tocrecommendations strict)
        .each { |x| ret[x] ||= options[x] }
      ext == :pdf && FontistUtils.has_fonts_manifest?(@processor, options) and
        ret[:mn2pdf] =
          { font_manifest: FontistUtils.location_manifest(@processor) }
      ret
    end
  end
end
