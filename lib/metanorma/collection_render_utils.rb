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
      # IDs for repo references are untyped by default
      docid = bib.at(ns("./docidentifier[not(@type)]")) ||
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

    def docconv
      doctype = @doctype.to_sym
      x = Asciidoctor.load nil, backend: doctype
      x.converter.doc_converter(DocOptionsNode.new(@directives))
    end

    # This may be redundant, may already have done this
    def concat_extract_files(filename)
      xml = Nokogiri::XML(File.read(filename, encoding: "UTF-8"), &:huge)
      docs = xml.xpath("//xmlns:doc-container").each_with_object([]) do |x, m|
        n = Nokogiri::XML::Document.new
        n.add_child(x.elements.first.remove)
        m << n
      end
      pref_file = docs.first.dup
      pref_file.at("//xmlns:bibdata").replace(xml.at("//xmlns:bibdata").to_xml)
      [pref_file, docs]
    end

    def docconv_convert(filename)
      pref_file, docs = concat_extract_files(filename)
      conv = docconv
      collection_conv = conv.dup
      body = docs.each_with_object([]) do |d, m|
        conv.convert_init(d.to_xml, "xxxx", false)
        html = conv.convert1(d, "xxx", ".")
        m << Nokogiri::XML(html).at("//body").children
      end
      collection_conv.options[:collection_doc] = body.map(&:to_xml).join

      def collection_conv.convert1(docxml, filename, dir)
        ret = Nokogiri::XML(super, &:huge)
        b = ret.at("//body")
        b.children = @options[:collection_doc]
        ret.to_xml
      end

      collection_conv.convert(filename, pref_file.to_xml, false)
    end

    def fail_update_bibitem(docid, identifier)
      error = "[metanorma] Cannot find crossreference to document #{docid} " \
              "in document #{identifier}."
      @log&.add("Cross-References", nil, error)
      Util.log(error, :warning)
    end

    def datauri_encode(docxml)
      docxml.xpath(ns("//image")).each do |i|
        i["src"] = Vectory::Utils::datauri(i["src"])
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

    class DocOptionsNode
      def initialize(directives)
        c = directives.detect { |x| x.is_a?(Hash) && x["word-coverpage"] }
        c and @wordcoverpage = c["word-coverpage"]
        c = directives.detect { |x| x.is_a?(Hash) && x["word-intropage"] }
        c and @wordcoverpage = c["word-intropage"]
      end

      def attr(key)
        case key
        when "wordcoverpage" then @wordcoverpage
        when "wordintropage" then @wordintropage
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

    # create the @meta class of isodoc, for populating Liquid,
    # with "navigation" set to the index bar.
    # extracted from the manifest
    def isodoc_populate
      @isodoc.info(@xml, nil)
      m = @xml.at(ns("//manifest"))
      { navigation: indexfile(m), nav_object: index_object(m),
        docrefs: liquid_docrefs,
        "prefatory-content": isodoc_builder(@xml.at(ns("//prefatory-content"))),
        "final-content": isodoc_builder(@xml.at(ns("//final-content"))),
        doctitle: m.at(ns("../bibdata/title"))&.text,
        docnumber: m.at(ns("../bibdata/docidentifier"))&.text }.each do |k, v|
          v and @isodoc.meta.set(
            k, v
          )
        end
    end

    def isodoc_builder(node)
      Nokogiri::HTML::Builder.new(encoding: "UTF-8") do |b|
        b.div do |div|
          node&.children&.each { |n| @isodoc.parse(n, div) }
        end
      end.doc.root.to_html
    end

    def ns(xpath)
      @isodoc.ns(xpath)
    end
  end
end
