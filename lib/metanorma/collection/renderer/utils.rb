require "marcel"

module Metanorma
  class Collection
    class Renderer
      def dir_name_cleanse(name)
        path = Pathname.new(name)
        clean_regex = /[<>:"|?*\p{Zs}]/
        fallback_sym = "_"
        path.absolute? or return name.gsub(clean_regex, fallback_sym)
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

      def new_hidden_ref(xml)
        ins = xml.at(ns("bibliography")) or
          xml.root << "<bibliography/>" and ins = xml.at(ns("bibliography"))
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

      def add_hidden_bibliography(xml, refs, current_id = nil)
        ins = new_hidden_ref(xml)
        current_html = if current_id
                         @files.get(current_id,
                                    :outputs)&.dig(:html)
                       else
                         nil
                       end
        refs.each do |k, v|
          url = @files.url(v, {})
          url = make_relative_path(current_html, url) if current_html
          ins << <<~XML
            <bibitem id="#{k}" anchor="#{k}">#{docid_xml(v)}<uri type='citation'>#{url}</uri></bibitem>
          XML
        end
      end

      def make_relative_path(from_file, to_file)
        return to_file if to_file.nil? || to_file.to_s.empty?
        return to_file if to_file.start_with?("http://", "https://", "#")

        from_dir = File.dirname(from_file)
        return to_file if from_dir == "."

        from_path = Pathname.new(from_dir)
        to_path = Pathname.new(to_file)
        to_path.relative_path_from(from_path).to_s
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
          raise ArgumentError,
                "Need to specify formats (xml,html,pdf,pdf-portfolio,doc)"
      end

      def pdfconv(added_options)
        flavor, taste_opts, x = pdfconv_prep
        fonts = [taste_opts[:fonts], added_options[:fonts]].compact.flatten
          .join(";")
        opts = @compile_options.merge(added_options.merge(taste_opts))
        opts[:fonts] = fonts
        x.converter.pdf_converter(PdfOptionsNode.new(flavor, opts))
      end

      def pdfconv_prep
        flavor = Util::taste2flavor(@flavor).to_sym
        taste_opts = Util::taste2isodoc_attrs(@flavor, :pdf)
        x = Asciidoctor.load nil, backend: flavor
        [flavor, taste_opts, x]
      end

      def fail_update_bibitem(docid, identifier)
        error = "[metanorma] Cannot find crossreference to document #{docid} " \
                "in document #{identifier}."
        @log&.add("METANORMA_2", nil, params: [docid, identifier])
        ::Metanorma::Util.log(error, :warning)
      end

      # Image relocation for collection rendering, in three ordered passes:
      # anchor every image target at the document that emitted it, then
      # inline SVGs, then encode what remains as data URIs.
      def datauri_encode(docxml, directory)
        anchor_image_targets(docxml, directory)
        inline_svg_images(docxml, directory)
        datauri_images(docxml, directory)
        docxml
      end

      # Image targets are emitted relative to the document that carries them
      # (metanorma#646). Each target must be anchored at the emitting
      # document's directory BEFORE it is resolved: Vectory's datauri
      # fallback tries the process working directory first, so a relative
      # target was resolved against wherever the build happened to run --
      # picking a same-named file from the wrong tree, or missing both
      # bases and failing the render. Data URIs, remote URLs and absolute
      # paths carry their own base and pass through; a target that anchors
      # to an existing file is pinned to that absolute path, so only the
      # file's bytes reach the output and the output is build-directory
      # independent. A target that anchors to nothing keeps its emitted
      # form, so a missing image stays a build-independent dangling
      # reference.
      def anchor_image_targets(docxml, directory)
        docxml.xpath(ns("//image")).each do |i|
          anchor_image_target(i, directory)
        end
      end

      def inline_svg_images(docxml, directory)
        docxml.xpath(ns("//image")).each do |i|
          read_in_if_svg(i, directory.sub(%r{(?<!=/)$}, "/"))
        end
      end

      def datauri_images(docxml, directory)
        docxml.xpath(ns("//image")).each do |i|
          (i["src"] && !i["src"].empty?) or next
          i["src"] = Vectory::Utils::datauri(i["src"], directory)
        end
      end

      def anchor_image_target(img, directory)
        src = img["src"]
        anchorable_base?(src) or return
        path = File.expand_path(src, directory)
        File.file?(path) or return
        img["src"] = path
      end

      # A target whose base is already determined cannot be re-anchored.
      def anchorable_base?(src)
        return false if src.nil? || src.empty?

        !(Vectory::Utils.datauri?(src) ||
          Vectory::Utils.url?(src) ||
          Vectory::Utils.absolute_path?(src))
      end

      def read_in_if_svg(img, localdir)
        img["src"] or return
        if img.elements.map(&:name).include?("svg")
          img["src"] = nil
          return
        end
        path = Vectory::Utils.svgmap_rewrite0_path(img["src"], localdir)
        svg = svg_in_path?(path) or return
        img.children = (Nokogiri::XML(svg).root)
        img["src"] = nil
        true
      end

      def svg_in_path?(path)
        File.file?(path) or return false
        type = Marcel::MimeType.for(name: path) or return false
        type == "image/svg+xml" or return false
        svg = File.read(path, encoding: "utf-8") or return false
        svg
      end

      class PdfOptionsNode
        def initialize(flavor, options)
          p = Metanorma::Registry.instance.find_processor(Util::taste2flavor(flavor))
          if ::Metanorma::Util::FontistHelper.has_custom_fonts?(p, options, {})
            @fonts_manifest =
              ::Metanorma::Util::FontistHelper.location_manifest(
                p, options,
                continue_without_fonts: options[:continue_without_fonts],
              )
          end
          @options = options
        end

        def attr(key)
          if key == "fonts-manifest" && @fonts_manifest
            @fonts_manifest
          else @options[key.to_sym]
          end
        end
      end

      # create the @meta class of isodoc, for populating Liquid,
      # with "navigation" set to the index bar.
      # extracted from the manifest
      def isodoc_populate
        @isodoc.info(@xml, nil)
        { navigation: indexfile(@manifest), nav_object: index_object(@manifest),
          bibdata: YAML.safe_load(@bibdata.to_yaml,
                                  permitted_classes: [Date, Symbol]),
          docrefs: liquid_docrefs(@manifest),
          "prefatory-content": isodoc_builder(@xml.at("//xmlns:prefatory-content")),
          "final-content": isodoc_builder(@xml.at("//xmlns:final-content")),
          doctitle: Array(@bibdata.title).first&.content,
          docnumber: Array(@bibdata.docidentifier).first&.content }.each do |k, v|
          v and @isodoc.meta.set(k, v)
        end
      end

      def isodoc_builder(node)
        node or return

        Nokogiri::HTML::Builder.new(encoding: "UTF-8") do |b|
          b.div do |div|
            node.children.each { |n| @isodoc.parse(n, div) }
          end
        end.doc.root.to_html
      end

      def eref2link(docxml, _presxml)
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
