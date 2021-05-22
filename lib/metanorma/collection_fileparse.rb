module Metanorma
  # XML collection renderer
  class CollectionRenderer
    # map locality type and label (e.g. "clause" "1") to id = anchor for
    # a document
    # Note: will only key clauses, which have unambiguous reference label in
    # locality. Notes, examples etc with containers are just plunked against
    # UUIDs, so that their IDs can at least be registered to be tracked
    # as existing.
    def read_anchors(xml)
      xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.i18n, {})
      xrefs.parse xml
      xrefs.get.each_with_object({}) do |(k, v), ret|
        ret[v[:type]] ||= {}
        index = if v[:container] || v[:label].nil? || v[:label].empty?
                  UUIDTools::UUID.random_create.to_s
                else v[:label]
                end
        ret[v[:type]][index] = k
      end
    end

    # @param id [String]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def xml_file(id, read)
      file = @xml.at(ns("//doc-container[@id = '#{id}']")).to_xml if read
      filename = "#{id}.html"
      [file, filename]
    end

    # @param bib [Nokogiri::XML::Element]
    # @param identifier [String]
    def update_bibitem(bib, identifier) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      docid = bib&.at(ns("./docidentifier"))&.text
      unless @files[docid]
        error = "[metanorma] Cannot find crossreference to document #{docid} "\
          "in document #{identifier}."
        @log.add("Cross-References", nil, error)
        Util.log(error, :warning)
        return
      end
      id = bib["id"]
      newbib = bib.replace(@files[docid][:bibdata])
      newbib.name = "bibitem"
      newbib["id"] = id
      newbib["hidden"] = "true"
      newbib&.at(ns("./ext"))&.remove
      _file, url = targetfile(@files[docid], relative: true, read: false,
                                             doc: !@files[docid][:attachment])
      uri_node = Nokogiri::XML::Node.new "uri", newbib
      uri_node[:type] = "citation"
      uri_node.content = url
      newbib.at(ns("./docidentifier")).previous = uri_node
    end

    # Resolves direct links to other files in collection
    # (repo(current-metanorma-collection/x),
    # and indirect links to other files in collection
    # (bibitem[@type = 'internal'] pointing to a file anchor
    # in another file in the collection)
    # @param file [String] XML content
    # @param identifier [String] docid
    # @param internal_refs [Hash{String=>Hash{String=>String}] schema name to anchor to filename
    # @return [String] XML content
    def update_xrefs(file, identifier, internal_refs)
      docxml = Nokogiri::XML(file)
      update_indirect_refs_to_docs(docxml, internal_refs)
      add_document_suffix(identifier, docxml)
      update_direct_refs_to_docs(docxml, identifier)
      svgmap_resolve(datauri_encode(docxml))
      docxml.xpath(ns("//references[not(./bibitem[not(@hidden) or "\
                      "@hidden = 'false'])]")).each do |f|
        f["hidden"] = "true"
      end
      docxml.to_xml
    end

    def datauri_encode(docxml)
      docxml.xpath(ns("//image")).each do |i|
        i["src"] = Metanorma::Utils::datauri(i["src"])
      end
      docxml
    end

    def svgmap_resolve(docxml)
      isodoc = IsoDoc::Convert.new({})
      docxml.xpath(ns("//svgmap//eref")).each do |e|
        href = isodoc.eref_target(e)
        next if href == "##{e['bibitemid']}" ||
          href =~ /^#/ && !docxml.at("//*[@id = '#{href.sub(/^#/, '')}']")

        e["target"] = href.strip
        e.name = "link"
        e&.elements&.remove
      end
      Metanorma::Utils::svgmap_rewrite(docxml, "")
    end

    # repo(current-metanorma-collection/ISO 17301-1:2016)
    # replaced by bibdata of "ISO 17301-1:2016" in situ as bibitem.
    # Any erefs to that bibitem id are replaced with relative URL
    # Preferably with anchor, and is a job to realise dynamic lookup
    # of localities.
    def update_direct_refs_to_docs(docxml, identifier)
      docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
        docid = b&.at(ns("./docidentifier[@type = 'repository']"))&.text
        next unless docid && %r{^current-metanorma-collection/}.match(docid)

        update_bibitem(b, identifier)
        update_anchors(b, docxml, docid)
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
      end
      docid = docxml.at(ns("//bibitem[@id = '#{schema}_#{id}']/"\
                           "docidentifier[@type = 'repository']")) or return
      docid.children = "current-metanorma-collection/#{file}"
      docid.previous = "<docidentifier type='X'>#{file}</docidentifier>"
    end

    # update crossrefences to other documents, to include
    # disambiguating document suffix on id
    def update_anchors(bib, docxml, _id) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      docid = bib&.at(ns("./docidentifier"))&.text
      docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
        if @files[docid]
          update_anchor_loc(bib, e, docid)
        else
          e << "<strong>** Unresolved reference to document #{docid}, "\
            "id #{e['bibitemid']}</strong>"
        end
      end
    end

    def update_anchor_loc(bib, e, docid)
      loc = e.at(ns(".//locality[@type = 'anchor']")) or
        return update_anchor_create_loc(bib, e, docid)
      document_suffix = Metanorma::Utils::to_ncname(docid)
      ref = loc.at(ns("./referenceFrom")) || return
      anchor = "#{ref.text}_#{document_suffix}"
      return unless @files[docid][:anchors].inject([]) do |m, (_, x)|
        m += x.values
      end.include?(anchor)

      ref.content = anchor
    end

    # if there is a crossref to another document, with no anchor, retrieve the
    # anchor given the locality, and insert it into the crossref
    def update_anchor_create_loc(bib, e, docid)
      ins = e.at(ns("./localityStack")) || return
      type = ins&.at(ns("./locality/@type"))&.text
      ref = ins&.at(ns("./locality/referenceFrom"))&.text
      (anchor = @files[docid][:anchors][type][ref]) || return
      ref_from = Nokogiri::XML::Node.new "referenceFrom", bib
      ref_from.content = anchor.sub(/^_/, "")
      locality = Nokogiri::XML::Node.new "locality", bib
      locality[:type] = "anchor"
      locality.add_child ref_from
      ins << locality
    end

    # gather internal bibitem references
    def gather_internal_refs
      @files.each_with_object({}) do |(_, x), refs|
        next if x[:attachment]

        file, = targetfile(x, read: true)
        Nokogiri::XML(file)
          .xpath(ns("//bibitem[@type = 'internal']/"\
        "docidentifier[@type = 'repository']")).each do |d|
          a = d.text.split(%r{/}, 2)
          a.size > 1 or next
          refs[a[0]] ||= {}
          refs[a[0]][a[1]] = true
        end
      end
    end

    # resolve file location for the target of each internal reference
    def locate_internal_refs
      refs = gather_internal_refs
      @files.keys.reject { |k| @files[k][:attachment] }.each do |identifier|
        locate_internal_refs1(refs, identifier, @files[identifier])
      end
      refs.each do |schema, ids|
        ids.each do |id, key|
          key == true and refs[schema][id] = "Missing:#{schema}:#{id}"
        end
      end
      refs
    end

    def locate_internal_refs1(refs, identifier, filedesc)
      file, _filename = targetfile(filedesc, read: true)
      docxml = Nokogiri::XML(file)
      refs.each do |schema, ids|
        ids.each_key do |id|
          n = docxml.at("//*[@id = '#{id}']") and
            n.at("./ancestor-or-self::*[@type = '#{schema}']") and
            refs[schema][id] = identifier
        end
      end
    end
  end
end
