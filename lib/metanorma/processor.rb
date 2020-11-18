# Registry of all Metanorma types and entry points
#
require "fontist"
require "fontist/manifest/install"

module Metanorma
  class Processor

    attr_reader :short
    attr_reader :input_format
    attr_reader :asciidoctor_backend

    def initialize
      raise "This is an abstract class!"
    end

    def fonts_manifest
      nil
    end

    def output_formats
      {
        xml: "xml",
        presentation: "presentation.xml",
        rxl: "rxl"
      }
    end

    def input_to_isodoc(file, filename, options = {})
      Metanorma::Input::Asciidoc.new.process(file, filename, @asciidoctor_backend, options)
    end

    # def input_to_isodoc(file, filename)
    #   raise "This is an abstract class!"
    # end

    def use_presentation_xml(ext)
      case ext
      when :html, :doc, :pdf then true
      else
        false
      end
    end

    def output(isodoc_node, inname, outname, format, options={})
      File.open(outname, "w:UTF-8") { |f| f.write(isodoc_node) }
    end

    def extract_options(file)
      Metanorma::Input::Asciidoc.new.extract_options(file)
    end

    def extract_metanorma_options(file)
      Metanorma::Input::Asciidoc.new.extract_metanorma_options(file)
    end

    def install_fonts(options={})
      if options[:no_install_fonts] || fonts_manifest.nil?
        Util.log("[fontinst] Skip font installation process", :debug)
        return
      end

      begin
        confirm = options[:agree_to_terms] ? "yes" : "no"
        Fontist::Manifest::Install.call(fonts_manifest, confirmation: confirm)
        Fontist::Manifest::Install.call(
          fonts_manifest,
          confirmation: options[:confirm_license] ? "yes" : "no"
        )
      rescue Fontist::Errors::LicensingError
        log_type = options[:continue_without_fonts] ? :error : :fatal
        Util.log("[fontinst] Error: License acceptance required to install a necessary font." \
          "Accept required licenses with: `metanorma setup --agree-to-terms`.", log_type)

      rescue Fontist::Errors::NonSupportedFontError
        Util.log("[fontinst] The font `#{font}` is not yet supported.", :info)
      end
    end
  end
end
