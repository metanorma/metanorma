module Metanorma
  class Sectionsplit
    def xref_preprocess(xml, _fileslookup, _identifier)
      key = (0...8).map { rand(65..90).chr }.join # random string
      xml.root["type"] = key # to force recognition of internal refs
      key
    end

    def xref_process(section, xml, key)
      svg_preprocess(section, Metanorma::Utils::to_ncname(@ident))
      refs = eref_to_internal_eref(section, xml, key)
      refs += xref_to_internal_eref(section, key)
      ins = new_hidden_ref(section)
      copied_refs = copy_repo_items_biblio(ins, section, xml)
      insert_indirect_biblio(ins, refs - copied_refs, key, xml)
    end

    def svg_preprocess(xml, document_suffix)
      xml.xpath("//m:svg", "m" => "http://www.w3.org/2000/svg").each do |s|
        m = svgmap_wrap(s)
        s.xpath(".//m:a", "m" => "http://www.w3.org/2000/svg").each do |a|
          /^#/.match? a["href"] or next
          a["href"] = a["href"].sub(/^#/, "")
          m << "<target href='#{a['href']}'>" \
               "<xref target='#{a['href']}_#{document_suffix}'/></target>"
        end
      end
      xml
    end

    def svgmap_wrap(svg)
      ret = svg.at("./ancestor::xmlns:svgmap") and return ret
      ret = svg.at("./ancestor::xmlns:figure")
      ret.wrap("<svgmap/>")
      svg.at("./ancestor::xmlns:svgmap")
    end

    def make_anchor(anchor)
      "<localityStack><locality type='anchor'><referenceFrom>" \
        "#{anchor}</referenceFrom></locality></localityStack>"
    end

    def xref_to_internal_eref(xml, key)
      bibitems = Util::gather_bibitems(xml)
      xml.xpath(ns("//xref")).each_with_object({}) do |x, m|
        x["bibitemid"] = "#{key}_#{x['target']}"
        m[x["bibitemid"]] = true
        xref_to_internal_eref_anchor(x, bibitems)
        x["type"] = key
        x.name = "eref"
      end.keys
    end

    def xref_to_internal_eref_anchor(xref, bibitems)
      t = xref["target"]
      if d = bibitems[t]&.at(ns("./docidentifier[@type = 'repository']"))
        m = %r{^([^/]+)}.match(d.text) and
          t.sub!(%r(#{m[0]}_), "")
      end
      xref << make_anchor(t)
      xref.delete("target")
    end

    def eref_to_internal_eref(section, xml, key)
      bibitems, bibitemids = eref_to_internal_eref_prep(section, xml)
      eref_to_internal_eref_select(section, xml, bibitems)
        .each_with_object([]) do |x, m|
          url = bibitems[x]&.at(ns("./uri[@type = 'citation']"))
          bibitemids[x]&.each do |e|
            id = eref_to_internal_eref1(e, key, url) and m << id
          end
        end
    end

    def eref_to_internal_eref_prep(section, xml)
      bibitems = Util::gather_bibitems(xml)
        .delete_if { |_, v| v["type"] == "internal" }
      bibitemids = Util::gather_bibitemids(section)
      [bibitems, bibitemids]
    end

    def eref_to_internal_eref1(elem, key, url)
      if url
        elem.name = "link"
        elem["target"] = url
        nil
      else
        elem["bibitemid"] = "#{key}_#{elem['bibitemid']}"
        elem << make_anchor(elem["bibitemid"])
        elem["type"] = key
        elem["bibitemid"]
      end
    end

    def eref_to_internal_eref_select(section, _xml, bibitems)
      refs = Util::gather_bibitemids(section).keys
      refs.uniq.reject do |x|
        b = bibitems[x] and (b["type"] == "internal" ||
                             b.at(ns("./docidentifier/@type = 'repository']")))
      end
    end

    # from standoc
    def new_hidden_ref(xmldoc)
      ins = xmldoc.at("bibliography") or
        xmldoc.root << "<bibliography/>" and ins = xmldoc.at("bibliography")
      ins.add_child("<references hidden='true' normative='false'/>").first
    end

    def copy_repo_items_biblio(ins, section, xml)
      bibitems = Util::gather_bibitems(section)
      xml.xpath(ns("//references/bibitem[docidentifier/@type = 'repository']"))
        .each_with_object([]) do |b, m|
          bibitems[b["id"]] or next
          # section.at("//*[@bibitemid = '#{b['id']}']") or next
          ins << b.dup
          m << b["id"]
        end
    end

    def insert_indirect_biblio(ins, refs, prefix, xml)
      bibitems = Util::gather_bibitems(xml)
        .delete_if { |_, v| v["type"] != "internal" }
      refs.each do |x|
        ins << if b = bibitems[x.sub(/^#{prefix}_/, "")]
                 b.dup.tap { |m| m["id"] = x }
        else new_indirect_bibitem(x, prefix)
        end
      end
    end

    def new_indirect_bibitem(ident, prefix)
      <<~BIBENTRY
        <bibitem id="#{ident}" type="internal">
        <docidentifier type="repository">#{ident.sub(/^#{prefix}_/, "#{prefix}/")}</docidentifier>
        </bibitem>
      BIBENTRY
    end
  end
end
