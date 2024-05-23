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

    def dup_bibitem(docid, bib)
      newbib = @files.get(docid, :bibdata).dup
      newbib.name = "bibitem"
      newbib["hidden"] = "true"
      newbib&.at("./*[local-name() = 'ext']")&.remove
      newbib["id"] = bib["id"]
      newbib
    end

    def get_bibitem_docid(bib, identifier)
      docid =
        bib.at(ns("./docidentifier[@type = 'metanorma-collection']")) ||
        bib.at(ns("./docidentifier[not(@type)]")) ||
        bib.at(ns("./docidentifier"))
      docid &&= docid_prefix(docid)
      if @files.get(docid) then docid
      else
        fail_update_bibitem(docid, identifier)
        nil
      end
    end

    def hide_refs(docxml)
      docxml.xpath(ns("//references[bibitem][not(./bibitem[not(@hidden) or " \
                      "@hidden = 'false'])]")).each do |f|
        f["hidden"] = "true"
      end
    end

    def strip_eref(eref)
      eref.xpath(ns("./locality | ./localityStack")).each(&:remove)
      eref.replace(eref.children)
    end

    def docid_to_citeas(bib)
      docid = bib.at(ns("./docidentifier[@primary = 'true']")) ||
        bib.at(ns("./docidentifier")) or return
      docid_prefix(docid)
    end

    def collect_erefs(docxml)
      docxml.xpath(ns("//eref"))
        .each_with_object({ citeas: {}, bibitemid: {} }) do |i, m|
        m[:citeas][i["citeas"]] = true
        m[:bibitemid][i["bibitemid"]] = true
      end
    end

    private

    def docid_prefix(docid)
      type = docid["type"]
      type == "metanorma-collection" and type = nil
      @c.decode(@isodoc
          .docid_prefix(type, docid.children.to_xml)).gsub(/\s/, " ")
    end

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

    def datauri_encode(docxml, directory)
      docxml.xpath(ns("//image")).each do |i|
        i["src"] = Vectory::Utils::datauri(i["src"], directory)
      end
      docxml
    end

    class PdfOptionsNode
      def initialize(doctype, options)
        docproc = Metanorma::Registry.instance.find_processor(doctype)
        if FontistUtils.has_custom_fonts?(docproc, options, {})
          @fonts_manifest = FontistUtils.location_manifest(docproc, options)
        end
      end

      def attr(key)
        if key == "fonts-manifest" && @fonts_manifest
          @fonts_manifest
        end
      end
    end

    def isodoc_create
      isodoc = Util::load_isodoc(@doctype)
      isodoc.i18n_init(@lang, @script, @locale) # read in internationalisation
      isodoc.metadata_init(@lang, @script, @locale, isodoc.i18n)
      isodoc.info(@xml, nil)
      isodoc
    end

    # create the @meta class of isodoc, for populating Liquid,
    # with "navigation" set to the index bar.
    # extracted from the manifest
    def isodoc_populate
      @isodoc.info(@xml, nil)
      { navigation: indexfile(@manifest), nav_object: index_object(@manifest),
        docrefs: liquid_docrefs(@manifest),
        "prefatory-content": isodoc_builder(@xml.at("//prefatory-content")),
        "final-content": isodoc_builder(@xml.at("//final-content")),
        doctitle: @bibdata.title.first.title.content,
        docnumber: @bibdata.docidentifier.first.id }.each do |k, v|
        v and @isodoc.meta.set(k, v)
      end
    end

    def isodoc_builder(node)
      node or return

      # Kludging namespace back in because of Shale brain damage
      doc = Nokogiri::XML(node.to_xml.sub(">", " xmlns='http://www.metanorma.org'>"))
      Nokogiri::HTML::Builder.new(encoding: "UTF-8") do |b|
        b.div do |div|
          doc.root.children&.each { |n| @isodoc.parse(n, div) }
        end
      end.doc.root.to_html
    end

    def ns(xpath)
      @isodoc.ns(xpath)
    end
  end
end
