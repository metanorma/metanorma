module Metanorma
  class Compile
    def xref_preprocess(xml)
      key = (0...8).map { rand(65..90).chr }.join # random string
      xml.root["type"] = key # to force recognition of internal refs
      key
    end

    def xref_process(section, xml, key)
      refs = eref_to_internal_eref(section, xml, key)
      refs += xref_to_internal_eref(section, key)
      ins = new_hidden_ref(section)
      copied_refs = copy_repo_items_biblio(ins, section, xml)
      insert_indirect_biblio(ins, refs - copied_refs, key)
    end

    def svg_preprocess(xml)
      xml.xpath("//m:svg", "m" => "http://www.w3.org/2000/svg").each do |s|
        m = svgmap_wrap(s)
        s.xpath(".//m:a", "m" => "http://www.w3.org/2000/svg").each do |a|
          next unless /^#/.match? a["href"]

          a["href"] = a["href"].sub(/^#/, "")
          m << "<target href='#{a['href']}'>" \
               "<xref target='#{a['href']}'/></target>"
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
      xml.xpath(ns("//xref")).each_with_object({}) do |x, m|
        x["bibitemid"] = "#{key}_#{x['target']}"
        x << make_anchor(x["target"])
        m[x["bibitemid"]] = true
        x.delete("target")
        x["type"] = key
        x.name = "eref"
      end.keys
    end

    def eref_to_internal_eref(section, xml, key)
      bibitems = Util::gather_bibitems(xml)
      bibitemids = Util::gather_bibitemids(section)
      eref_to_internal_eref_select(section, xml, bibitems)
        .each_with_object([]) do |x, m|
        url = bibitems[x]&.at(ns("./uri[@type = 'citation']"))
        bibitemids[x]&.each do |e|
          id = eref_to_internal_eref1(e, key, url)
          id and m << id
        end
      end
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
      #refs = section.xpath("//*/@bibitemid").map { |x| x.text } # rubocop:disable Style/SymbolProc
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

    def insert_indirect_biblio(ins, refs, prefix)
      refs.each do |x|
        ins << <<~BIBENTRY
          <bibitem id="#{x}" type="internal">
          <docidentifier type="repository">#{x.sub(/^#{prefix}_/, "#{prefix}/")}</docidentifier>
          </bibitem>
        BIBENTRY
      end
    end
  end
end
