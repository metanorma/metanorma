module Metanorma
  class Collection
    class Renderer
      def svg_datauri(docxml, docid)
        rel = @files.get(docid, :rel_path)
        parent = @files.get(docid, :parentid) and
          rel = @files.get(parent, :rel_path)
        # if sectionsplit, use orig file dir
        dir = File.join(@dirname, File.dirname(rel))
        datauri_encode(docxml, dir)
      end

      def svgmap_resolve(docxml, docid, presxml)
        ids = @files.get(docid, :ids)
        docxml = svg_unnest(svg_datauri(docxml, docid))
        isodoc = IsoDoc::PresentationXMLConvert.new({})
        isodoc.bibitem_lookup(docxml)
        tag = presxml ? "fmt-eref" : "eref"
        docxml.xpath(ns("//svgmap//#{tag}")).each do |e|
          svgmap_resolve_eref(e, isodoc, docxml, ids, presxml)
        end
        docxml.xpath(ns("//svgmap/target")).each do |t| # undo Presentation XML: Vectory takes eref not fmt-eref
          n = t.at(ns(".//fmt-link | .//fmt-xref | .//fmt-eref")) or next
          n.name = n.name.sub(/^fmt-/, "")
          t.children = n
        end
        Vectory::SvgMapping.new(docxml, "").call
        docxml.xpath(ns("//svgmap")).each { |s| isodoc.svgmap_extract(s) }
      end

      def svg_unnest(docxml)
        docxml.xpath(ns("//svgmap//image[.//*[name() = 'image']]")).each do |i|
          s = i.elements.detect { |e| e.name == "svg" } and
            i.replace(s)
        end
        docxml
      end

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
