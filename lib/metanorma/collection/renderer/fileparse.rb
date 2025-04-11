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
        #require "debug"; binding.b if /This document is also unrelated/.match?(xml.to_xml)
        #warn (/fmt-title/.match?(xml.to_xml) ? "*** PRESENTATION" : "*** SEMANTIC")
        @nested || sso or
          Metanorma::Collection::XrefProcess::xref_process(xml, xml, nil, docid,
                                                           @isodoc, sso)
        @ncnames = {}
        @nested or update_indirect_refs_to_docs(xml, docid, internal_refs, sso)
        @files.add_document_suffix(docid, xml)
        @nested or update_sectionsplit_refs_to_docs(xml, internal_refs, sso)
        update_direct_refs_to_docs(xml, docid, sso)
        hide_refs(xml)
        sso and eref2link(xml, sso)
        @nested or svgmap_resolve(xml, docid, sso)
        xml.to_xml
      end

      ## sso files are Presentation XML; otherwise, Semantic XML
      def update_xrefs_prep(file, docid)
        docxml = file.is_a?(String) ? Nokogiri::XML(file, &:huge) : file
        supply_repo_ids(docxml)
        sso = @files.get(docid, :sectionsplit_output)
        [docxml, sso]
      end

      def update_sectionsplit_refs_to_docs(docxml, internal_refs, presxml)
        Util::gather_citeases(docxml, presxml).each do |k, v|
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

      ANCHOR_XPATH = "xmlns:locality[@type = 'anchor']/xmlns:referenceFrom"
        .freeze

      def update_sectionsplit_eref_to_doc(eref, internal_refs, doclist, opts)
        a = eref.at("./xmlns:localityStack/#{ANCHOR_XPATH}") or return
        doc = internal_refs[opts[:key]]["#{a.text}_#{opts[:target_suffix]}"]
        bibitemid = Metanorma::Utils::to_ncname("#{doc}_#{opts[:source_suffix]}")
        eref["bibitemid"] = bibitemid
        doclist[bibitemid] ||= doc
        doclist
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

      # repo(current-metanorma-collection/ISO 17301-1:2016)
      # replaced by bibdata of "ISO 17301-1:2016" in situ as bibitem.
      # Any erefs to that bibitem id are replaced with relative URL
      # Preferably with anchor, and is a job to realise dynamic lookup
      # of localities.
      def update_direct_refs_to_docs(docxml, identifier, presxml)
        erefs, erefs_no_anchor, anchors, erefs1 =
          update_direct_refs_to_docs_prep(docxml, presxml)
        # Merge
        docxml.xpath(ns("//bibitem")).each do |b|
          docid = b.at(ns("./docidentifier[@type = 'repository']")) or next
          strip_unresolved_repo_erefs(identifier, docid, erefs1, b) or next
          update_bibitem(b, identifier)
          docid = docid_to_citeas(b) or next
          erefs[docid] and
            update_anchors(b, docid, erefs[docid], erefs_no_anchor[docid],
                           anchors[docid])
        end
      end

      # Hash(docid) of arrays
      def update_direct_refs_to_docs_prep(docxml, presxml)
        erefs = Util::gather_citeases(docxml, presxml)
        no_anchor = erefs.keys.each_with_object({}) { |k, m| m[k] = [] }
        anchors = erefs.keys.each_with_object({}) { |k, m| m[k] = [] }
        erefs.each do |k, v|
          v.each do |e|
            if loc = e.at(".//#{ANCHOR_XPATH}") then anchors[k] << loc
            else no_anchor[k] << e end
          end
        end
        #require "debug"; binding.b
        [erefs, no_anchor, anchors, Util::gather_bibitemids(docxml, presxml)]
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
      def update_indirect_refs_to_docs(docxml, _docidentifier, internal_refs, presxml)
        @@in_update ||= 0
        before = Time.now
        bib, erefs, doc_suffix, doc_type, f = update_indirect_refs_prep(docxml, presxml)
        add_suffix_outer = doc_suffix && doc_type
        internal_refs.each do |schema, ids|
          add_suffix = add_suffix_outer && doc_type != schema
          ids.each do |id, file|
            # HOT: 50M+ invocations on some collections, so every minor (de)optimization matters
            f_file = f[file]
            f_file ||= f[file] = @files.url_parent_id(file)
            k = indirect_ref_key(schema, id, doc_suffix, add_suffix)
            update_indirect_refs_to_docs1(f_file, k, file, bib, erefs)
          end
        end
        @@in_update += Time.now - before
        puts "@@in_update = #{@@in_update} total, #{Time.now - before} now"
      end

      def update_indirect_refs_prep(docxml, presxml)
        @updated_anchors = {}
        @indirect_keys = Hash.new { |h, k| h[k] = {} }
        [Util::gather_bibitems_with_doc_ids(docxml, ns("./docidentifier[@type = 'repository']")),
         Util::gather_bibitemids_with_anchors(docxml, presxml, ".//#{ANCHOR_XPATH}"),
         docxml.root["document_suffix"], docxml.root["type"], {}]
      end

      # KILL
      def indirect_ref_key(schema, id, doc_suffix, doc_type)
        /^#{schema}_/.match?(id) and return id
        key = [schema, id, doc_suffix, doc_type].join("::")
        x = @indirect_keys[key] and return x
        ret = "#{schema}_#{id}"
        doc_suffix && doc_type && doc_type != schema and
          ret = "#{ret}_#{doc_suffix}"
        @indirect_keys[key] = ret
        ret
      end

      def indirect_ref_key(schema, id, doc_suffix, add_suffix)
        return id if id[schema.length] == "_" and id.start_with?(schema)
        #key = "#{schema}_#{id}"
        x = @indirect_keys[schema][id] and return x
        @indirect_keys[schema][id] = if add_suffix
                                  schema + "_" + id + "_" + doc_suffix
                                else
                                   schema + "_" + id
                                end
      end

      # KILL
      def indirect_ref_keyx(schema, id, doc_suffix, doc_type)
        return id if id[schema.length] == "_" and id.start_with?(schema)
        ret = schema + "_" + id
        doc_suffix && doc_type && doc_type != schema and
          ret = ret + "_" + doc_suffix
        ret
      end

      def update_indirect_refs_to_docs1(filec, key, file, bibitems, erefs)
        erefs[key]&.each do |e|
          e.eref["citeas"] = file
          update_indirect_refs_to_docs_anchor(e, file, filec[:url],
                                              filec[:parentid])
        end
        update_indirect_refs_to_docs_docid(bibitems[key], file)
      end

      def update_indirect_refs_to_docs_anchor(eref, file, url, parentid)
        a = eref.anchor or return
        existing = a.text
        anchor = if url then existing
                 else
                   #suffix_anchor_indirect(existing, suffix)
                   #k = "#{existing}_#{file}"
                   #@ncnames[k] ||= Metanorma::Utils::to_ncname(k)
                   parentid and file = parentid + "_" + file
                   @indirect_keys[existing] ||= {}
                   @indirect_keys[existing][file] ||= Metanorma::Utils::to_ncname(existing + "_" + file)
                 end
        @updated_anchors[existing] or a.children = anchor
        @updated_anchors[anchor] = true
      end

      def update_indirect_refs_to_docs_docid(bib, file)
        docid = bib&.doc_id or return
        docid.children = "current-metanorma-collection/#{file}"
        docid.previous =
          "<docidentifier type='metanorma-collection'>#{file}</docidentifier>"
      end

      # bottleneck
      def update_anchors(bib, docid, erefs, erefs_no_anchor, erefs_anchors)
        @files.get(docid) or error_anchor(erefs, docid)
        has_anchors, url, ncn_docid = update_anchors_prep(docid)
        erefs_no_anchor.each do |e|
          update_anchor_create_loc(bib, e, docid)
        end
        !url && has_anchors or return
        erefs_anchors.each do |e|
          update_anchors1(docid, ncn_docid, e)
        end
      end

      def update_anchors1(docid, ncn_docid, anchor)
        @concat_anchors[anchor.text] ||= "#{ncn_docid}_#{anchor.text}"
        if @files.get(docid).dig(:anchors_lookup, @concat_anchors[anchor.text])
          anchor.content = @concat_anchors[anchor.text]
        end
      end

      def update_anchors_prep(docid)
        @concat_anchors = {}
        [@files.get(docid)&.key?(:anchors_lookup), @files.url?(docid),
         Metanorma::Utils::to_ncname(docid)]
      end

      # encode both prefix and suffix to NCName
      def suffix_anchor_indirect(prefix, suffix)
        k = "#{prefix}_#{suffix}"
        @ncnames[k] ||= Metanorma::Utils::to_ncname(k)
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
