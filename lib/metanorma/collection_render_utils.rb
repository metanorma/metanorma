module Metanorma
  class CollectionRenderer
    def dir_name_cleanse(name)
      path = Pathname.new(name)
      clean_regex = /[<>:"|?*]/
      fallback_sym = "_"
      return name.gsub(clean_regex, fallback_sym) unless path.absolute?

      File.join(path.dirname,
                path.basename.to_s.gsub(clean_regex, fallback_sym))
    end

    private

    def create_non_existing_directory(output_directory)
      !File.exist?(output_directory) and
        FileUtils.mkdir_p(output_directory)
    end

    def format_sort(formats)
      ret = []
      formats.include?(:xml) and ret << :xml
      formats.include?(:presentation) and ret << :presentation
      a = %i(presentation xml)
      ret + formats.reject { |i| a.include? i }
    end

    # @param options [Hash]
    # @raise [ArgumentError]
    def check_options(options)
      (options[:format].is_a?(Array) && (FORMATS & options[:format]).any?) or
        raise ArgumentError, "Need to specify formats (xml,html,pdf,doc)"
    end

    def pdfconv
      doctype = @doctype.to_sym
      x = Asciidoctor.load nil, backend: doctype
      x.converter.pdf_converter(PdfOptionsNode.new(doctype,
                                                   @compile_options))
    end

    def fail_update_bibitem(docid, identifier)
      error = "[metanorma] Cannot find crossreference to document #{docid} " \
              "in document #{identifier}."
      @log&.add("Cross-References", nil, error)
      Util.log(error, :warning)
    end

    def datauri_encode(docxml)
      docxml.xpath(ns("//image")).each do |i|
        i["src"] = Metanorma::Utils::datauri(i["src"])
      end
      docxml
    end

    class PdfOptionsNode
      def initialize(doctype, options)
        docproc = Metanorma::Registry.instance.find_processor(doctype)
        if FontistUtils.has_fonts_manifest?(docproc, options)
          @fonts_manifest = FontistUtils.location_manifest(docproc)
        end
      end

      def attr(key)
        if key == "fonts-manifest" && @fonts_manifest
          @fonts_manifest
        end
      end
    end

    class Dummy
      def attr(_key); end
    end

    def isodoc_create
      x = Asciidoctor.load nil, backend: @doctype.to_sym
      isodoc = x.converter.html_converter(Dummy.new) # to obtain Isodoc class
      isodoc.i18n_init(@lang, @script, @locale) # read in internationalisation
      isodoc.metadata_init(@lang, @script, @locale, isodoc.i18n)
      isodoc.info(@xml, nil)
      isodoc
    end

    def isodoc_populate
      # create the @meta class of isodoc, for populating Liquid,
      # with "navigation" set to the index bar.
      # extracted from the manifest
      @isodoc.meta.set(:navigation, indexfile(@xml.at(ns("//manifest"))))
      @isodoc.meta.set(:docrefs, liquid_docrefs)
      @isodoc.meta.set(:"prefatory-content",
                       isodoc_builder(@isodoc,
                                      @xml.at(ns("//prefatory-content"))))
      @isodoc.meta.set(:"final-content",
                       isodoc_builder(isodoc,
                                      @xml.at(ns("//final-content"))))
      @isodoc.info(@xml, nil)
    end

    def isodoc_builder(isodoc, node)
      Nokogiri::HTML::Builder.new(encoding: "UTF-8") do |b|
        b.div do |div|
          node&.children&.each { |n| isodoc.parse(n, div) }
        end
      end.doc.root.to_html
    end

    def ns(xpath)
      @isodoc.ns(xpath)
    end
  end
end
