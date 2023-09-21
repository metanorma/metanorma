module Metanorma
  # XML collection renderer
  class CollectionRenderer
    # @param bib [Nokogiri::XML::Element]
    # @param identifier [String]
    def update_bibitem(bib, identifier)
      docid = get_bibitem_docid(bib, identifier) or return
      newbib = dup_bibitem(docid, bib)
      _file, url = @files
        .targetfile_id(docid, relative: true, read: false,
                              doc: !@files.get(docid, :attachment))
      dest = newbib.at("./docidentifier") || newbib.at(ns("./docidentifier"))
      dest.previous = "<uri type='citation'>#{url}</uri>"
      bib.replace(newbib)
    end

    def get_bibitem_docid(bib, identifier)
      # IDs for repo references are untyped by default
      docid = bib.at(ns("./docidentifier[not(@type)]")) ||
        bib.at(ns("./docidentifier"))
      docid &&= @c.decode(@isodoc
          .docid_prefix(docid["type"], docid.children.to_xml)).gsub(/\s/, " ")
      if @files.get(docid) then docid
      else
        fail_update_bibitem(docid, identifier)
        nil
      end
    end

    def dup_bibitem(docid, bib)
      newbib = @files.get(docid, :bibdata).dup
      newbib.name = "bibitem"
      newbib["hidden"] = "true"
      newbib&.at("./*[local-name() = 'ext']")&.remove
      newbib["id"] = bib["id"]
      newbib
    end

    # Resolves direct links to other files in collection
    # (repo(current-metanorma-collection/x),
    # and indirect links to other files in collection
    # (bibitem[@type = 'internal'] pointing to a file anchor
    # in another file in the collection)
    # @param file [String] XML content
    # @param identifier [String] docid
    # @param internal_refs [Hash{String=>Hash{String=>String}] schema name to
    #   anchor to filename
    # @return [String] XML content
    def update_xrefs(file, identifier, internal_refs)
      docxml = file.is_a?(String) ? Nokogiri::XML(file, &:huge) : file
      @files.get(identifier, :xrefs_processed) or
        update_xrefs1(docxml, identifier, internal_refs)
      docxml.to_xml
    end

    def update_xrefs1(docxml, identifier, internal_refs)
      ids = @files.get(identifier, :ids)
      supply_repo_ids(docxml)
      update_indirect_refs_to_docs(docxml, internal_refs)
      @files.add_document_suffix(identifier, docxml)
      update_direct_refs_to_docs(docxml, identifier)
      svgmap_resolve(datauri_encode(docxml), ids)
      hide_refs(docxml)
      docxml.to_xml
    end

    def hide_refs(docxml)
      docxml.xpath(ns("//references[bibitem][not(./bibitem[not(@hidden) or " \
                      "@hidden = 'false'])]")).each do |f|
        f["hidden"] = "true"
      end
    end

    def supply_repo_ids(docxml)
      docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
        b.at(ns("./docidentifier[@type = 'repository']")) and next
        b.xpath(ns("./docidentifier")).each do |docid|
          id = @isodoc
            .docid_prefix(docid["type"], docid.children.to_xml)
          @files.get(id) or next
          docid.next = "<docidentifier type='repository'>" \
                       "current-metanorma-collection/#{id}</docidentifier>"
        end
      end
    end

    def svgmap_resolve(docxml, ids)
      isodoc = IsoDoc::PresentationXMLConvert.new({})
      isodoc.bibitem_lookup(docxml)
      docxml.xpath(ns("//svgmap//eref")).each do |e|
        svgmap_resolve1(e, isodoc, docxml, ids)
      end
      Metanorma::Utils::svgmap_rewrite(docxml, "")
    end

    def svgmap_resolve1(eref, isodoc, _docxml, ids)
      href = isodoc.eref_target(eref)
      return if href == "##{eref['bibitemid']}" ||
        # (href =~ /^#/ && !docxml.at("//*[@id = '#{href.sub(/^#/, '')}']"))
        (href =~ /^#/ && !ids[href.sub(/^#/, "")])

      eref["target"] = href.strip
      eref.name = "link"
      eref&.elements&.remove
    end

    # repo(current-metanorma-collection/ISO 17301-1:2016)
    # replaced by bibdata of "ISO 17301-1:2016" in situ as bibitem.
    # Any erefs to that bibitem id are replaced with relative URL
    # Preferably with anchor, and is a job to realise dynamic lookup
    # of localities.
    def update_direct_refs_to_docs(docxml, identifier)
      erefs = collect_erefs(docxml)
      docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
        docid = b.at(ns("./docidentifier[@type = 'repository']"))
        (docid && %r{^current-metanorma-collection/}.match(docid.text)) or next
        update_bibitem(b, identifier)
        docid = docid_to_citeas(b) or next
        erefs[:citeas][docid] and update_anchors(b, docxml, docid)
      end
    end

    def docid_to_citeas(bib)
      docid = bib.at(ns("./docidentifier[@primary = 'true']")) ||
        bib.at(ns("./docidentifier")) or return
      @c.decode(@isodoc
          .docid_prefix(docid["type"], docid.children.to_xml))
    end

    def collect_erefs(docxml)
      docxml.xpath(ns("//eref"))
        .each_with_object({ citeas: {}, bibitemid: {} }) do |i, m|
        m[:citeas][i["citeas"]] = true
        m[:bibitemid][i["bibitemid"]] = true
      end
    end

    # Resolve erefs to a container of ids in another doc,
    # to an anchor eref (direct link)
    def update_indirect_refs_to_docs(docxml, internal_refs)
      internal_refs.each do |schema, ids|
        ids.each do |id, file|
          update_indirect_refs_to_docs1(docxml, schema, id, file)
        end
      end
    end

    def update_indirect_refs_to_docs1(docxml, schema, id, file)
      docxml.xpath(ns("//eref[@bibitemid = '#{schema}_#{id}']")).each do |e|
        e["citeas"] = file
        a = e.at(ns(".//locality[@type = 'anchor']/referenceFrom")) and
          a.children = "#{a.text}_#{Metanorma::Utils::to_ncname(file)}"
      end
      docid = docxml.at(ns("//bibitem[@id = '#{schema}_#{id}']/" \
                           "docidentifier[@type = 'repository']")) or return
      docid.children = "current-metanorma-collection/#{file}"
      docid.previous =
        "<docidentifier type='metanorma-collection'>#{file}</docidentifier>"
    end

    # update crossrefences to other documents, to include
    # disambiguating document suffix on id
    def update_anchors(bib, docxml, docid) # rubocop:disable Metrics/AbcSize
      docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
        if @files.get(docid) then update_anchor_loc(bib, e, docid)
        else
          e << "<strong>** Unresolved reference to document #{docid} " \
               "from eref</strong>"
        end
      end
    end

    def update_anchor_loc(bib, eref, docid)
      loc = eref.at(ns(".//locality[@type = 'anchor']")) or
        return update_anchor_create_loc(bib, eref, docid)
      ref = loc.at(ns("./referenceFrom")) or return
      anchor = "#{ref.text}_#{Metanorma::Utils::to_ncname(docid)}"
      return unless @files.get(docid, :anchors).inject([]) do |m, (_, x)|
        m += x.values
      end.include?(anchor)

      ref.content = anchor
    end

    # if there is a crossref to another document, with no anchor, retrieve the
    # anchor given the locality, and insert it into the crossref
    def update_anchor_create_loc(_bib, eref, docid)
      ins = eref.at(ns("./localityStack")) or return
      type = ins.at(ns("./locality/@type"))&.text
      type = "clause" if type == "annex"
      ref = ins.at(ns("./locality/referenceFrom"))&.text
      anchor = @files.get(docid, :anchors).dig(type, ref) or return
      ins << "<locality type='anchor'><referenceFrom>#{anchor.sub(/^_/, '')}" \
             "</referenceFrom></locality>"
    end

    # gather internal bibitem references
    def gather_internal_refs
      @files.keys.each_with_object({}) do |i, refs|
        @files.get(i, :attachment) and next
        file, = @files.targetfile_id(i, read: true)
        gather_internal_refs1(file, refs)
      end
    end

    def gather_internal_refs1(file, refs)
      Nokogiri::XML(file, &:huge)
        .xpath(ns("//bibitem[@type = 'internal']/" \
                  "docidentifier[@type = 'repository']")).each do |d|
        a = d.text.split(%r{/}, 2)
        a.size > 1 or next
        refs[a[0]] ||= {}
        refs[a[0]][a[1]] = true
      end
    end

    # resolve file location for the target of each internal reference
    def locate_internal_refs
      refs = gather_internal_refs
      @files.keys.reject { |k| @files.get(k, :attachment) }.each do |ident|
        locate_internal_refs1(refs, ident, @isodoc.docid_prefix("", ident.dup))
      end
      refs.each do |schema, ids|
        ids.each do |id, key|
          key == true and refs[schema][id] = "Missing:#{schema}:#{id}"
        end
      end
      refs
    end

    def locate_internal_refs1(refs, identifier, ident)
      xml, t = locate_internal_refs1_prep(identifier, ident)
      refs.each do |schema, ids|
        ids.keys.select { |id| t[id] }.each do |id|
          # TODO may need more optimisation
          n = xml.at("//*[@id = '#{id}']") and
            n.at("./ancestor-or-self::*[@type = '#{schema}']") and
            refs[schema][id] = identifier
        end
      end
    end

    def locate_internal_refs1_prep(identifier, ident)
      file, _filename = @files.targetfile_id(ident, read: true)
      xml = Nokogiri::XML(file, &:huge)
      # t1 = xml.xpath("//*/@id").each_with_object({}) { |i, x| x[i.text] = true }
      suffix = Metanorma::Utils::to_ncname(identifier)
      transformed_keys = @files.get(ident, :ids).transform_keys do |x|
        x&.sub(/_#{suffix}/, "")
      end
      [xml, transformed_keys]
    end
  end
end
