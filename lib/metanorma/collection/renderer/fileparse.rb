module Metanorma
  class Collection
    class Renderer
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
      def update_xrefs(file, docid, internal_refs)
        xml, sso = update_xrefs_prep(file, docid)
        @nested || sso or
          Metanorma::Collection::XrefProcess::xref_process(xml, xml, nil, docid,
                                                           @isodoc)
        @nested or update_indirect_refs_to_docs(xml, docid, internal_refs)
        @files.add_document_suffix(docid, xml)
        @nested or update_sectionsplit_refs_to_docs(xml, internal_refs)
        update_direct_refs_to_docs(xml, docid)
        hide_refs(xml)
        sso and eref2link(xml)
        @nested or svgmap_resolve(xml, docid)
        xml.to_xml
      end

      def update_xrefs_prep(file, docid)
        docxml = file.is_a?(String) ? Nokogiri::XML(file, &:huge) : file
        supply_repo_ids(docxml)
        sso = @files.get(docid, :sectionsplit_output)
        [docxml, sso]
      end

      def update_sectionsplit_refs_to_docs(docxml, internal_refs)
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

      def eref2link(docxml)
        isodoc = IsoDoc::PresentationXMLConvert.new({})
        isodoc.bibitem_lookup(docxml)
        isodoc.eref2link(docxml)
      end

      BIBITEM_NOT_REPO_XPATH = "//bibitem[not(ancestor::bibitem)]" \
        "[not(./docidentifier[@type = 'repository'])]".freeze

      def supply_repo_ids(doc)
        doc.xpath(ns(BIBITEM_NOT_REPO_XPATH)).each do |b|
          b.xpath(ns("./docidentifier")).each do |docid|
            id = @isodoc.docid_prefix(docid["type"], docid.children.to_xml)
            @files.get(id) or next
            @files.get(id, :indirect_key) and next # will resolve as indirect key
            docid.next = docid_xml(id)
          end
        end
      end

      def svg_datauri(docxml, docid)
        rel = @files.get(docid, :rel_path)
        parent = @files.get(docid, :parentid) and
          rel = @files.get(parent, :rel_path)
        # if sectionsplit, use orig file dir
        dir = File.join(@dirname, File.dirname(rel))
        datauri_encode(docxml, dir)
      end

      def svgmap_resolve(docxml, docid)
        ids = @files.get(docid, :ids)
        docxml = svg_unnest(svg_datauri(docxml, docid))
        isodoc = IsoDoc::PresentationXMLConvert.new({})
        isodoc.bibitem_lookup(docxml)
        docxml.xpath(ns("//svgmap//eref")).each do |e|
          svgmap_resolve_eref(e, isodoc, docxml, ids)
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

      def svgmap_resolve_eref(eref, isodoc, _docxml, ids)
        href = isodoc.eref_target(eref) or return
        href = href[:link]
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
        %r{^current-metanorma-collection/(?!Missing:)}.match?(bib_docid.text) and
          return true
        @nested and return false
        erefs[bibitem["id"]]&.each { |x| x.parent and strip_eref(x) }
        false
      end

      # Resolve erefs to a container of ids in another doc,
      # to an anchor eref (direct link)
      def update_indirect_refs_to_docs(docxml, _docidentifier, internal_refs)
        bibitems, erefs = update_indirect_refs_to_docs_prep(docxml)
        internal_refs.each do |schema, ids|
          s = "#{schema}_"
          ids.each do |id, file|
            k = indirect_ref_key(s, schema, id, docxml)
            update_indirect_refs_to_docs1(docxml, k, file, bibitems, erefs)
          end
        end
      end

      def update_indirect_refs_to_docs_prep(docxml)
        @updated_anchors = {}
        [Util::gather_bibitems(docxml), Util::gather_bibitemids(docxml)]
      end

      def indirect_ref_key(schema_, schema, id, docxml)
        /^#{schema_}/.match?(id) and return id
        ret = schema_ + id
        suffix = docxml.root["document_suffix"] or return ret
        (k = docxml.root["type"]) && k != schema or return ret
        "#{ret}_#{suffix}"
      end

      #OLD
      def indirect_ref_key1(schema, id, docxml)
        /^#{schema}_/.match?(id) and return id
        ret = "#{schema}_#{id}"
        suffix = docxml.root["document_suffix"]
        (k = docxml.root["type"]) && k != schema && suffix and
          ret = "#{ret}_#{suffix}"
        ret
      end

      def update_indirect_refs_to_docs1(_docxml, key, file, bibitems, erefs)
        erefs[key]&.each do |e|
          e["citeas"] = file
          update_indirect_refs_to_docs_anchor(e, file)
        end
        update_indirect_refs_to_docs_docid(bibitems[key], file)
      end

      def update_indirect_refs_to_docs_anchor(eref, file)
        a = eref.at(ns(".//locality[@type = 'anchor']/referenceFrom")) or return
        suffix = file
        @files.get(file) && p = @files.get(file, :parentid) and
          suffix = "#{p}_#{suffix}"
        existing = a.text
        anchor = existing
        @files.url?(file) or
          anchor = Metanorma::Utils::to_ncname("#{anchor}_#{suffix}")
        @updated_anchors[existing] or a.children = anchor
        @updated_anchors[anchor] = true
      end

      def update_indirect_refs_to_docs_docid(bib, file)
        docid = bib&.at(ns("./docidentifier[@type = 'repository']")) or return
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
            e << msg
            strip_eref(e)
            @log&.add("Cross-References", e, msg)
          end
        end
      end

      def update_anchor_loc(bib, eref, docid)
        loc = eref.at(".//xmlns:locality[@type = 'anchor']") or
          return update_anchor_create_loc(bib, eref, docid)
        a = @files.get(docid, :anchors) or return
        ref = loc.elements&.first or return
        anchor = suffix_anchor(ref.text, docid)
        a.values.detect { |x| x.value?(anchor) } or return
        ref.content = anchor
      end

      #OLD
      def update_anchor_loc1(bib, eref, docid)
        loc = eref.at(".//xmlns:locality[@type = 'anchor']") or
          return update_anchor_create_loc(bib, eref, docid)
        ref = loc.at("./xmlns:referenceFrom") or return
        anchor = suffix_anchor(ref, docid)
        a = @files.get(docid, :anchors) or return
        a.inject([]) { |m, (_, x)| m + x.values }
          .include?(anchor) or return
        ref.content = anchor
      end

      def suffix_anchor(ref, docid)
        @ncnames[docid] ||= "#{Metanorma::Utils::to_ncname(docid)}_"
        @files.url?(docid) or return ref
        @ncnames[docid] + ref
      end

      #OLD
       def suffix_anchor1(ref, docid)
        @ncnames[docid] ||= Metanorma::Utils::to_ncname(docid)
        anchor = ref.text
        @files.url?(docid) or anchor = "#{@ncnames[docid]}_#{anchor}"
        anchor
      end

      # if there is a crossref to another document, with no anchor, retrieve the
      # anchor given the locality, and insert it into the crossref
      def update_anchor_create_loc(_bib, eref, docid)
        ins = eref.at(ns("./localityStack")) or return
        type = ins.at(ns("./locality/@type"))&.text
        type = "clause" if type == "annex"
        ref = ins.at(ns("./locality/referenceFrom"))&.text
        a = @files.get(docid, :anchors).dig(type, ref) or return
        ins << "<locality type='anchor'><referenceFrom>#{a.sub(/^_/, '')}" \
               "</referenceFrom></locality>"
      end
    end
  end
end
