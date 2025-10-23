module Metanorma
  class Collection
    class Renderer
      def dir_name_cleanse(name)
        path = Pathname.new(name)
        clean_regex = /[<>:"|?*\p{Zs}]/
        fallback_sym = "_"
        return name.gsub(clean_regex, fallback_sym) unless path.absolute?

        File.join(path.dirname,
                  path.basename.to_s.gsub(clean_regex, fallback_sym))
      end

      def dup_bibitem(docid, bib)
        newbib = deep_detached_clone(@files.get(docid, :bibdata))
        newbib.name = "bibitem"
        newbib["hidden"] = "true"
        newbib&.at("./*[local-name() = 'ext']")&.remove
        newbib["id"] = bib["id"]
        bib["anchor"] and newbib["anchor"] = bib["anchor"]
        newbib
      end

      def deep_detached_clone(node)
        Nokogiri::XML(node.to_xml).root
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

      def new_hidden_ref(xmldoc)
        ins = xmldoc.at(ns("bibliography")) or
          xmldoc.root << "<bibliography/>" and ins = xmldoc.at(ns("bibliography"))
        ins.at(ns("./references[@hidden = 'true']")) or
          ins.add_child("<references hidden='true' normative='false'/>").first
      end

      def strip_eref(eref)
        eref.xpath(ns("./locality | ./localityStack")).each(&:remove)
        eref.replace(eref.children)
      end

      def docid_to_citeas(bib)
        docid = bib.at(ns("./docidentifier[@primary = 'true']")) ||
          bib.at(ns("./docidentifier")) or return
        ::Metanorma::Collection::Util::key(docid_prefix(docid))
      end

      def collect_erefs(docxml, presxml)
        tag = presxml ? "fmt-eref" : "eref"
        docxml.xpath(ns("//#{tag}"))
          .each_with_object({ citeas: {}, bibitemid: {} }) do |i, m|
          m[:citeas][i["citeas"]] = true
          m[:bibitemid][i["bibitemid"]] = true
        end
      end

      def docid_xml(val)
        "<docidentifier type='repository'>current-metanorma-collection/" \
          "#{val}</docidentifier>"
      end

      def add_hidden_bibliography(xmldoc, refs)
        ins = new_hidden_ref(xmldoc)
        refs.each do |k, v|
          url = @files.url(v, {})
          ins << <<~XML
            <bibitem id="#{k}" anchor="#{k}">#{docid_xml(v)}<uri type='citation'>#{url}</uri></bibitem>
          XML
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
        flavor = @flavor.to_sym
        x = Asciidoctor.load nil, backend: flavor
        x.converter.pdf_converter(PdfOptionsNode.new(flavor,
                                                     @compile_options))
      end

      def fail_update_bibitem(docid, identifier)
        error = "[metanorma] Cannot find crossreference to document #{docid} " \
                "in document #{identifier}."
        @log&.add("METANORMA_2", nil, params: [docid, identifier])
        ::Metanorma::Util.log(error, :warning)
      end

      def datauri_encode(docxml, directory)
        docxml.xpath(ns("//image")).each do |i|
          read_in_if_svg(i, directory.sub(%r{(?<!=/)$}, "/")) and i["src"] = nil
        end
        docxml.xpath(ns("//image")).each do |i| # rubocop:disable Style/CombinableLoops
          i["src"] && !i["src"].empty? or next
          i["src"] = Vectory::Utils::datauri(i["src"], directory)
        end
        docxml
      end

      def read_in_if_svg(img, localdir)
        img["src"] or return false
        img.elements.map(&:name).include?("svg") and return true
        path = Vectory::Utils.svgmap_rewrite0_path(img["src"], localdir)
        svg = svg_in_path?(path) or return false
        img.children = (Nokogiri::XML(svg).root)
        true
      end

      def svg_in_path?(path)
        File.file?(path) or return false
        types = MIME::Types.type_for(path) or return false
        types.first == "image/svg+xml" or return false
        svg = File.read(path, encoding: "utf-8") or return false
        svg
      end

      class PdfOptionsNode
        def initialize(flavor, options)
          p = Metanorma::Registry.instance.find_processor(flavor)
          if ::Metanorma::Util::FontistHelper.has_custom_fonts?(p, options, {})
            @fonts_manifest =
              ::Metanorma::Util::FontistHelper.location_manifest(p, options)
          end
        end

        def attr(key)
          if key == "fonts-manifest" && @fonts_manifest
            @fonts_manifest
          end
        end
      end

      # create the @meta class of isodoc, for populating Liquid,
      # with "navigation" set to the index bar.
      # extracted from the manifest
      def isodoc_populate
        @isodoc.info(@xml, nil)
        { navigation: indexfile(@manifest), nav_object: index_object(@manifest),
          bibdata: @bibdata.to_hash, docrefs: liquid_docrefs(@manifest),
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

      def eref2link(docxml, presxml)
        isodoc = IsoDoc::PresentationXMLConvert.new({})
        isodoc.bibitem_lookup(docxml)
        isodoc.eref2link(docxml)
      end

      def error_anchor(erefs, docid)
        erefs.each do |e|
          msg = "<strong>** Unresolved reference to document #{docid} " \
            "from eref</strong>"
          e << msg
          strip_eref(e)
          @log&.add("METANORMA_3", e, params: [docid])
        end
      end

      def ns(xpath)
        @isodoc.ns(xpath)
      end
    end
  end
end
