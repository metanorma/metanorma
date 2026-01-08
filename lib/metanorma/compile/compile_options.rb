require "csv"

module Metanorma
  class Compile
    module CompileOptions
      def require_libraries(options)
        options&.dig(:require)&.each { |r| require r }
      end

      def extract_xml_options(file)
        xml = Nokogiri::XML(file, &:huge)
        if xml.root
          @registry.root_tags.each do |k, v|
            return { type: k } if v == xml.root.name
          end
        end
        {}
      end

      def extract_options(filename, options)
        o = options_in_file(filename)
        extract_flavor_options(options, o)
        extract_dir_options(options, o, filename)
        extract_extension_options(options, o)
        options[:format] ||= :asciidoc
        options[:filename] = filename
        options[:fontlicenseagreement] ||= "no-install-fonts"
        options[:novalid] = o[:novalid] if o[:novalid]
        options
      end

      def extract_extension_options(opt, doc_opt)
        opt[:extension_keys] == [:all] and opt[:extension_keys] = []
        ext = opt[:extension_keys] || []
        doc_opt[:extensions] == "all" and doc_opt[:extensions] = ""
        ext1 = (doc_opt[:extensions] || "").split(/, */).map(&:to_sym)
        !ext1.empty? && ext.empty? and opt[:extension_keys] = ext1
        opt[:extension_keys]&.empty? and opt[:extension_keys] = nil
      end

      def options_in_file(filename)
        content = read_file(filename)
        Metanorma::Input::Asciidoc.new.extract_metanorma_options(content)
          .merge(extract_xml_options(content))
      end

      def extract_flavor_options(options, options_in_file)
        options[:type] ||= options_in_file[:type]
        options[:type] = options[:type]&.to_sym
        options[:supplied_type] = options[:type]
        t = @registry.alias(options[:type]) and options[:type] = t
      end

      def extract_dir_options(options, options_in_file, filename)
        filename.is_a?(Tempfile) and return
        dir = filename.sub(%r(/[^/]+$), "/")
        options_in_file[:relaton] and
          options[:relaton] ||= File.join(dir,
                                          options_in_file[:relaton])
        options_in_file[:sourcecode] and
          options[:sourcecode] ||= File.join(dir,
                                             options_in_file[:sourcecode])
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
        get_isodoc_fileparams(options, ret)
        copy_isodoc_options_attrs(options, ret)
        font_manifest_mn2pdf(options, ret, ext)
        ret[:output_formats]&.select! do |k, _|
          options[:extension_keys].include?(k)
        end
        ret[:log] = @log
        ret
      end

      def get_isodoc_fileparams(options, ret)
        %i(i18nyaml relatonrenderconfig).each do |k|
          dir = File.dirname(options[:filename])
          ret[k] or next
          (Pathname.new ret[k]).absolute? or
            ret[k] = File.join(dir, ret[k])
        end
      end

      def copy_isodoc_options_attrs(options, ret)
        ret[:datauriimage] = true if options[:datauriimage]
        ret[:sourcefilename] = options[:filename]
        %i(bare sectionsplit install_fonts fonts baseassetpath
           aligncrosselements tocfigures toctables tocrecommendations strict)
          .each { |x| ret[x] ||= options[x] }
      end

      def font_manifest_mn2pdf(options, ret, ext)
        custom_fonts = Util::FontistHelper
          .has_custom_fonts?(@processor, options, ret)

        ext == :pdf && custom_fonts and
          ret[:mn2pdf] = {
            font_manifest: Util::FontistHelper
              .location_manifest(@processor, ret),
          }
      end
    end
  end
end
