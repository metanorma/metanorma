require "yaml"

module Metanorma
  class Compile
    # assume we pass in Presentation XML, but we want to recover Semantic XML
    def sectionsplit_convert(input_filename, file, output_filename = nil,
                             opts = {})
      @isodoc = IsoDoc::Convert.new({})
      input_filename += ".xml" unless input_filename.match?(/\.xml$/)
      File.exist?(input_filename) or
        File.open(input_filename, "w:UTF-8") { |f| f.write(file) }
      presxml = File.read(input_filename, encoding: "utf-8")
      @openmathdelim, @closemathdelim = @isodoc.extract_delims(presxml)
      xml, filename, dir = @isodoc.convert_init(presxml, input_filename, false)
      build_collection(xml, presxml, output_filename || filename, dir, opts)
    end

    def ns(xpath)
      @isodoc.ns(xpath)
    end

    def build_collection(xml, presxml, filename, dir, opts = {})
      base = File.basename(filename)
      collection_setup(base, dir)
      files = sectionsplit(xml, base, dir)
      collection_manifest(base, files, xml, presxml, dir).render(
        { format: %i(html), output_folder: "#{filename}_collection",
          coverpage: File.join(dir, "cover.html") }.merge(opts),
      )
    end

    def collection_manifest(filename, files, origxml, _presxml, dir)
      File.open(File.join(dir, "#{filename}.html.yaml"), "w:UTF-8") do |f|
        f.write(collectionyaml(files, origxml))
      end
      Metanorma::Collection.parse File.join(dir, "#{filename}.html.yaml")
    end

    def collection_setup(filename, dir)
      FileUtils.mkdir_p "#{filename}_collection" if filename
      FileUtils.mkdir_p dir
      File.open(File.join(dir, "cover.html"), "w:UTF-8") do |f|
        f.write(coll_cover)
      end
    end

    def coll_cover
      <<~COVER
        <html><head/>
            <body>
              <h1>{{ doctitle }}</h1>
              <h2>{{ docnumber }}</h2>
              <nav>{{ navigation }}</nav>
            </body>
        </html>
      COVER
    end

    SPLITSECTIONS =
      [["//preface/*", "preface"], ["//sections/*", "sections"],
       ["//annex", nil],
       ["//bibliography/*[not(@hidden = 'true')]", "bibliography"],
       ["//indexsect", nil]].freeze

    def sectionsplit(xml, filename, dir)
      @key = xref_preprocess(xml)
      @splitdir = dir
      out = emptydoc(xml)
      SPLITSECTIONS.each_with_object([]) do |n, ret|
        xml.xpath(ns(n[0])).each do |s|
          ret << sectionfile(xml, out, "#{filename}.#{ret.size}", s, n[1])
        end
      end
    end

    def emptydoc(xml)
      out = xml.dup
      out.xpath(
        ns("//preface | //sections | //annex | //bibliography/clause | "\
           "//bibliography/references[not(@hidden = 'true')] | //indexsect"),
      ).each(&:remove)
      out
    end

    def sectionfile(fulldoc, xml, file, chunk, parentnode)
      fname = create_sectionfile(fulldoc, xml.dup, file, chunk, parentnode)
      { order: chunk["displayorder"].to_i, url: fname,
        title: titlerender(chunk) }
    end

    def create_sectionfile(xml, out, file, chunk, parentnode)
      ins = out.at(ns("//misccontainer")) || out.at(ns("//bibdata"))
      if parentnode
        ins.next = "<#{parentnode}/>"
        ins.next.add_child(chunk.dup)
      else ins.next = chunk.dup
      end
      xref_process(out, xml, @key)
      outname = "#{file}.xml"
      File.open(File.join(@splitdir, outname), "w:UTF-8") { |f| f.write(out) }
      outname
    end

    def xref_preprocess(xml)
      svg_preprocess(xml)
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
          m << "<target href='#{a['href']}'>"\
               "<xref target='#{a['href']}'/></target>"
        end
      end
    end

    def svgmap_wrap(svg)
      ret = svg.at("./ancestor::xmlns:svgmap") and return ret
      ret = svg.at("./ancestor::xmlns:figure")
      ret.wrap("<svgmap/>")
      svg.at("./ancestor::xmlns:svgmap")
    end

    def make_anchor(anchor)
      "<localityStack><locality type='anchor'><referenceFrom>"\
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
      eref_to_internal_eref_select(section, xml).each_with_object([]) do |x, m|
        url = xml.at(ns("//bibitem[@id = '#{x}']/uri[@type = 'citation']"))
        section.xpath(("//*[@bibitemid = '#{x}']")).each do |e|
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

    def eref_to_internal_eref_select(section, xml)
      refs = section.xpath(("//*/@bibitemid")).map { |x| x.text } # rubocop:disable Style/SymbolProc
      refs.uniq.reject do |x|
        xml.at(ns("//bibitem[@id = '#{x}'][@type = 'internal']")) ||
          xml.at(ns("//bibitem[@id = '#{x}']"\
                    "[docidentifier/@type = 'repository']"))
      end
    end

    # from standoc
    def new_hidden_ref(xmldoc)
      ins = xmldoc.at("bibliography") or
        xmldoc.root << "<bibliography/>" and ins = xmldoc.at("bibliography")
      ins.add_child("<references hidden='true' normative='false'/>").first
    end

    def copy_repo_items_biblio(ins, section, xml)
      xml.xpath(ns("//references/bibitem[docidentifier/@type = 'repository']"))
        .each_with_object([]) do |b, m|
        section.at("//*[@bibitemid = '#{b['id']}']") or next
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

    def recursive_string_keys(hash)
      case hash
      when Hash then hash.map { |k, v| [k.to_s, recursive_string_keys(v)] }.to_h
      when Enumerable then hash.map { |v| recursive_string_keys(v) }
      else
        hash
      end
    end

    def titlerender(section)
      title = section.at(ns("./title")) or return "[Untitled]"
      t = title.dup
      t.xpath(ns(".//tab | .//br")).each { |x| x.replace(" ") }
      t.xpath(ns(".//strong")).each { |x| x.replace(x.children) }
      t.children.to_xml
    end

    def collectionyaml(files, xml)
      ret = {
        directives: ["presentation-xml", "bare-after-first"],
        bibdata: {
          title: {
            type: "title-main", language: @lang,
            content: xml.at(ns("//bibdata/title")).text
          },
          type: "collection",
          docid: {
            type: xml.at(ns("//bibdata/docidentifier/@type")).text,
            id: xml.at(ns("//bibdata/docidentifier")).text,
          },
        },
        manifest: {
          level: "collection", title: "Collection",
          docref: files.sort_by { |f| f[:order] }.each.map do |f|
            { fileref: f[:url], identifier: f[:title] }
          end
        },
      }
      recursive_string_keys(ret).to_yaml
    end
  end
end
