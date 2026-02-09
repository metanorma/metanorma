module Metanorma
  class Collection
    class Renderer
      # Converts SVG images to data URIs for inline embedding
      def svg_datauri(docxml, docid)
        rel = @files.get(docid, :rel_path)
        parent = @files.get(docid, :parentid) and
          rel = @files.get(parent, :rel_path)
        # if sectionsplit, use orig file dir
        dir = File.join(@dirname, File.dirname(rel))
        datauri_encode(docxml, dir)
      end

      # Resolves SVG map references and processes SVG ID disambiguation.
      #
      # Delegates SVG manipulation to Vectory gem, which handles:
      # 1. Document-level suffixing for cross-document ID disambiguation
      # 2. Index-based suffixing for multiple svgmaps within one document
      # 3. Link remapping and SVG extraction
      #
      # Metanorma's role: State requirements and coordinate the workflow.
      # Vectory's role: Handle all SVG ID manipulation internally.
      #
      # @param docxml [Nokogiri::XML::Document] The document XML to process
      # @param docid [String] Document identifier for retrieving suffix
      # @param presxml [Boolean, nil] Whether this is presentation XML
      def svgmap_resolve(docxml, docid, presxml)
        ids, docxml, isodoc, tag = svgmap_resolve_prep(docxml, docid, presxml)

        # Stage 1: Resolve EREF references to their targets
        resolve_svgmap_erefs(docxml, tag, isodoc, ids, presxml)

        # Stage 2: Normalize prefixes (Vectory expects eref, not fmt-eref)
        normalize_svgmap_prefixes(docxml)

        # Stage 3: Process with Vectory
        # Pass document suffix to Vectory as id_suffix for proper SVG ID disambiguation.
        # Vectory handles both id_suffix (document-level) and index suffix internally.
        doc_suffix = @files.get(docid, :document_suffix)
        Vectory::SvgMapping.new(docxml, "", id_suffix: doc_suffix).call

        # Stage 4: Extract processed SVG content
        extract_svgmap_content(docxml, isodoc)
      end

      # Prepares document and context for svgmap resolution
      def svgmap_resolve_prep(docxml, docid, presxml)
        ids = @files.get(docid, :ids)
        docxml = svg_unnest(svg_datauri(docxml, docid))
        isodoc = IsoDoc::PresentationXMLConvert.new({})
        isodoc.bibitem_lookup(docxml)
        tag = presxml ? "fmt-eref" : "eref"
        [ids, docxml, isodoc, tag]
      end

      private

      # Resolves EREF elements within svgmap to their actual link targets
      def resolve_svgmap_erefs(docxml, tag, isodoc, ids, presxml)
        docxml.xpath(ns("//svgmap//#{tag}")).each do |e|
          svgmap_resolve_eref(e, isodoc, docxml, ids, presxml)
        end
      end

      # Converts fmt-eref/fmt-link/fmt-xref back to eref/link/xref
      # Vectory expects non-prefixed element names for proper processing
      def normalize_svgmap_prefixes(docxml)
        svgmap_fmt_prefix_remove(docxml)
      end

      # Extracts processed SVG content from svgmap elements
      def extract_svgmap_content(docxml, isodoc)
        docxml.xpath(ns("//svgmap")).each { |s| isodoc.svgmap_extract(s) }
      end

      # Converts Presentation XML fmt- prefix back to standard element names
      # Vectory expects eref/link/xref, not fmt-eref/fmt-link/fmt-xref
      def svgmap_fmt_prefix_remove(docxml)
        docxml.xpath(ns("//svgmap/target")).each do |t|
          n = t.at(ns(".//fmt-link | .//fmt-xref | .//fmt-eref")) or next
          n.name = n.name.sub(/^fmt-/, "")
          t.children = n
        end
      end

      # Removes nested image elements within svgmap, flattening the structure
      def svg_unnest(docxml)
        docxml.xpath(ns("//svgmap//image[.//*[name() = 'image']]")).each do |i|
          s = i.elements.detect { |e| e.name == "svg" } and
            i.replace(s)
        end
        docxml
      end

      # Resolves a single EREF element to its target link
      def svgmap_resolve_eref(eref, isodoc, _docxml, ids, presxml)
        href = isodoc.eref_target(eref) or return
        href = href[:link]
        href == "##{eref['bibitemid']}" ||
          (href =~ /^#/ && !ids[href.sub(/^#/, "")]) and return
        eref["target"] = href.strip
        eref.name = presxml ? "fmt-link" : "link"
        eref.elements&.remove
      end
    end
  end
end
