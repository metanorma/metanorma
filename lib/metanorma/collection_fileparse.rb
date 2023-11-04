module Metanorma
  # XML collection renderer
  class CollectionRenderer
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

    # Resolves references to other files in the collection. Three routines:
    # 1. Eref to a document that has been split into multiple documents
    # (sectionsplit) are resolved to direct eref to the split document
    # 2. Indirect erefs to a file anchor in an unknwon file in the collection
    # (bibitem[@type = 'internal'] ) are resolved to direct eref to the
    # containing document
    # 3. Direct erefs to other files in collection
    # (repo(current-metanorma-collection/x) are resolved to hyperlinks
    # @param file [String] XML content
    # @param identifier [String] docid
    # @param internal_refs [Hash{String=>Hash{String=>String}] schema name to
    #   anchor to filename
    # @return [String] XML content
    def update_xrefs(file, identifier, internal_refs)
      docxml = file.is_a?(String) ? Nokogiri::XML(file, &:huge) : file
      supply_repo_ids(docxml)
      update_indirect_refs_to_docs(docxml, identifier, internal_refs)
      @files.add_document_suffix(identifier, docxml)
      update_sectionsplit_refs_to_docs(docxml, internal_refs)
      update_direct_refs_to_docs(docxml, identifier)
      hide_refs(docxml)
      @files.get(identifier, :sectionsplit_output) and eref2link(docxml)
      svgmap_resolve(datauri_encode(docxml), @files.get(identifier, :ids))
      docxml.to_xml
    end

    def update_sectionsplit_refs_to_docs(docxml, internal_refs)
      @nested and return
      Util::gather_citeases(docxml).each do |k, v|
        (@files.get(k) && @files.get(k, :sectionsplit)) or next
        opts = { key: @files.get(k, :indirect_key),
                 source_suffix: docxml.root["document_suffix"],
                 target_suffix: @files.get(k, :document_suffix) }
        refs = v.each_with_object({}) do |eref, m|
          update_sectionsplit_eref_to_doc(eref, internal_refs, m, opts)
        end
        add_hidden_bibliography(docxml, refs)
      end
    end

    def update_sectionsplit_eref_to_doc(eref, internal_refs, doclist, opts)
      a = eref.at(ns("./localityStack/locality[@type = 'anchor']/" \
                     "referenceFrom")) or return
      doc = internal_refs[opts[:key]]["#{a.text}_#{opts[:target_suffix]}"]
      bibitemid = Metanorma::Utils::to_ncname("#{doc}_#{opts[:source_suffix]}")
      eref["bibitemid"] = bibitemid
      doclist[bibitemid] ||= doc
      doclist
    end

    def new_hidden_ref(xmldoc)
      ins = xmldoc.at(ns("bibliography")) or
        xmldoc.root << "<bibliography/>" and ins = xmldoc.at(ns("bibliography"))
      ins.at(ns("./referenced[@hidden = 'true']")) or
        ins.add_child("<references hidden='true' normative='false'/>").first
    end

    def add_hidden_bibliography(xmldoc, refs)
      ins = new_hidden_ref(xmldoc)
      refs.each do |k, v|
        _, url = @files.targetfile_id(v, {})
        ins << <<~XML
          <bibitem id="#{k}">
            <docidentifier type="repository">current-metanorma-collection/#{v}</docidentifier>
            <uri type='citation'>#{url}</uri>
          </bibitem>
        XML
      end
    end

    def eref2link(docxml)
      isodoc = IsoDoc::PresentationXMLConvert.new({})
      isodoc.bibitem_lookup(docxml)
      isodoc.eref2link(docxml)
    end

    def supply_repo_ids(doc)
      doc.xpath(
        ns("//bibitem[not(ancestor::bibitem)]" \
           "[not(./docidentifier[@type = 'repository'])]"),
      ).each do |b|
        b.xpath(ns("./docidentifier")).each do |docid|
          id = @isodoc.docid_prefix(docid["type"], docid.children.to_xml)
          @files.get(id) or next
          @files.get(id, :indirect_key) and next # will resolve as indirect key
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
      docxml.xpath(ns("//svgmap")).each { |s| isodoc.svgmap_extract(s) }
    end

    def svgmap_resolve1(eref, isodoc, _docxml, ids)
      href = isodoc.eref_target(eref) or return
      href == "##{eref['bibitemid']}" ||
        (href =~ /^#/ && !ids[href.sub(/^#/, "")]) and return
      eref["target"] = href.strip
      eref.name = "link"
      eref.elements&.remove
    end

    # repo(current-metanorma-collection/ISO 17301-1:2016)
    # replaced by bibdata of "ISO 17301-1:2016" in situ as bibitem.
    # Any erefs to that bibitem id are replaced with relative URL
    # Preferably with anchor, and is a job to realise dynamic lookup
    # of localities.
    def update_direct_refs_to_docs(docxml, identifier)
      erefs, erefs1 = update_direct_refs_to_docs_prep(docxml)
      docxml.xpath(ns("//bibitem")).each do |b|
        docid = b.at(ns("./docidentifier[@type = 'repository']")) or next
        strip_unresolved_repo_erefs(identifier, docid, erefs1, b) or next
        update_bibitem(b, identifier)
        docid = docid_to_citeas(b) or next
        erefs[docid] and update_anchors(b, docid, erefs[docid])
      end
    end

    def update_direct_refs_to_docs_prep(docxml)
      @ncnames = {}
      [Util::gather_citeases(docxml), Util::gather_bibitemids(docxml)]
    end

    # strip erefs if they are repository erefs, but do not point to a document
    # within the current collection. This can happen if a collection consists
    # of many documents, but not all are included in the current collection.
    # Do not do this if this is a sectionsplit collection or a nested manifest.
    # Return false if bibitem is not to be further processed
    def strip_unresolved_repo_erefs(_document_id, bib_docid, erefs, bibitem)
      %r{^current-metanorma-collection/}.match?(bib_docid.text) &&
        !%r{^current-metanorma-collection/Missing:}.match?(bib_docid.text) and
        return true
      @nested and return false
      erefs[bibitem["id"]]&.each { |x| strip_eref(x) }
      false
    end

    # Resolve erefs to a container of ids in another doc,
    # to an anchor eref (direct link)
    def update_indirect_refs_to_docs(docxml, _docidentifier, internal_refs)
      @nested and return
      bibitems = Util::gather_bibitems(docxml)
      erefs = Util::gather_bibitemids(docxml)
      internal_refs.each do |schema, ids|
        ids.each do |id, file|
          k = indirect_ref_key(schema, id, docxml)
          update_indirect_refs_to_docs1(docxml, k,
                                        file, bibitems, erefs)
        end
      end
    end

    def indirect_ref_key(schema, id, docxml)
      ret = "#{schema}_#{id}"
      k = docxml.root["type"] and
        ret = "#{k}_#{ret}_#{docxml.root['document_suffix']}"
      ret
    end

    def update_indirect_refs_to_docs1(_docxml, key, file, bibitems, erefs)
      erefs[key]&.each do |e|
        e["citeas"] = file
        a = e.at(ns(".//locality[@type = 'anchor']/referenceFrom")) and
          a.children = "#{a.text}_#{Metanorma::Utils::to_ncname(file)}"
      end
      docid = bibitems[key]&.at(ns("./docidentifier[@type = 'repository']")) or
        return
      docid.children = "current-metanorma-collection/#{file}"
      docid.previous =
        "<docidentifier type='metanorma-collection'>#{file}</docidentifier>"
    end

    # update crossrefences to other documents, to include
    # disambiguating document suffix on id
    def update_anchors(bib, docid, erefs)
      erefs.each do |e|
        if @files.get(docid) then update_anchor_loc(bib, e, docid)
        else
          msg = "<strong>** Unresolved reference to document #{docid} " \
            "from eref</strong>"
          @log&.add("Cross-References", e, msg)
          e << msg
        end
      end
    end

    def update_anchor_loc(bib, eref, docid)
      loc = eref.at(".//xmlns:locality[@type = 'anchor']") or
        return update_anchor_create_loc(bib, eref, docid)
      @ncnames[docid] ||= Metanorma::Utils::to_ncname(docid)
      ref = loc.at("./xmlns:referenceFrom") or return
      anchor = "#{ref.text}_#{@ncnames[docid]}"
      @files.get(docid, :anchors).inject([]) do |m, (_, x)|
        m += x.values
      end.include?(anchor) or return
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
  end
end
