# frozen_string_literal: true

require "isodoc"

module Metanorma
  # XML collection renderer
  class CollectionRenderer
    # hash for each document in collection of document identifier to:
    # document reference (fileref or id), type of document reference,
    # and bibdata entry for that file
    # @param path [String] path to collection
    # @return [Hash{String=>Hash}]
    def read_files(path) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      files = {}
      @xml.xpath(ns("//docref")).each do |d|
        identifier = d.at(ns("./identifier")).text
        files[identifier] = if d["fileref"]
                              { type: "fileref",
                                ref: File.join(path, d["fileref"]) }
                            else { type: "id", ref: d["id"] }
                            end
        file, _filename = targetfile(files[identifier], true)
        xml = Nokogiri::XML(file)
        add_document_suffix(identifier, xml)
        files[identifier][:anchors] = read_anchors(xml)
        files[identifier][:bibdata] = xml.at(ns("//bibdata"))
      end
      files
    end

    def add_suffix_to_attributes(doc, suffix, tag_name, attribute_name)
      doc.xpath(ns("//#{tag_name}[@#{attribute_name}]")).each do |elem|
        elem.attributes[attribute_name].value =
          "#{elem.attributes[attribute_name].value}_#{suffix}"
      end
    end

    def add_document_suffix(identifier, doc)
      document_suffix = Asciidoctor::Standoc::Cleanup.to_ncname(identifier)
      [%w[* id],
      %w[* bibitemid],
      %w[review from],
      %w[review to],
      %w[index to],
      %w[xref target],
      %w[callout target]]
      .each do |(tag_name, attribute_name)|
        add_suffix_to_attributes(doc, document_suffix, tag_name, attribute_name)
      end
    end

    # map locality type and label (e.g. "clause" "1") to id = anchor for
    # a document
    def read_anchors(xml)
      ret = {}
      xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.i18n, {})
      xrefs.parse xml
      xrefs.get.each do |k, v|
        ret[v[:type]] ||= {}
        index = v[:container] || v[:label].nil? || v[:label].empty? ? 
          UUIDTools::UUID.random_create.to_s : v[:label]
        # Note: will only key clauses, which have unambiguous reference label in locality.
        # Notes, examples etc with containers are just plunked agaisnt UUIDs, so that their
        # IDs can at least be registered to be tracked as existing.
        ret[v[:type]][index] = k
      end
      ret
    end

    # return file contents + output filename for each file in the collection,
    # given a docref entry
    # @param data [Hash]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def targetfile(data, read = false)
      if data[:type] == "fileref" then ref_file data[:ref], read
      else xml_file data[:id], read
      end
    end

    # @param ref [String]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def ref_file(ref, read)
      file = File.read(ref, encoding: "utf-8") if read
      filename = ref.sub(/\.xml$/, ".html")
      [file, filename]
    end

    # @param id [String]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def xml_file(id, read)
      file = @xml.at(ns("//doc-container[@id = '#{id}']")).to_xml if read
      filename = id + ".html"
      [file, filename]
    end

    # @param bib [Nokogiri::XML::Element]
    # @param identifier [String]
    def update_bibitem(bib, identifier) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      docid = bib&.at(ns("./docidentifier"))&.text
      unless @files[docid]
        warn "Cannot find crossreference to document #{docid} in document #{identifier}!"
        return
      end
      id = bib["id"]
      newbib = bib.replace(@files[docid][:bibdata])
      newbib.name = "bibitem"
      newbib["id"] = id
      newbib["hidden"] = "true"
      newbib&.at(ns("./ext"))&.remove
      _file, url = targetfile(@files[docid], false)
      uri_node = Nokogiri::XML::Node.new "uri", newbib
      uri_node[:type] = "citation"
      uri_node.content = url
      newbib.at(ns("./docidentifier")).previous = uri_node
    end

    # Resolves direct links to other files in collection (repo(current-metanorma-collection/x),
    # and indirect links to other files in collection (bibitem[@type = 'internal'] pointing to a file anchor
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
      docxml.xpath(ns("//references[not(./bibitem[not(@hidden) or @hidden = 'false'])]")).each do |f|
        f["hidden"] = "true"
      end
      docxml.to_xml
    end

    # repo(current-metanorma-collection/ISO 17301-1:2016)
    # replaced by bibdata of "ISO 17301-1:2016" in situ as bibitem.
    # Any erefs to that bibitem id are replaced with relative URL
    # Preferably with anchor, and is a job to realise dynamic lookup of localities.
    def update_direct_refs_to_docs(docxml, identifier)
      docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
        docid = b&.at(ns("./docidentifier[@type = 'repository']"))&.text
        next unless docid && %r{^current-metanorma-collection/}.match(docid)
        update_bibitem(b, identifier)
        update_anchors(b, docxml, docid)
      end
    end

    # Resolve erefs to a container of ids in another doc, to an anchor eref (direct link)
    def update_indirect_refs_to_docs(docxml, internal_refs)
      internal_refs.each do |schema, ids|
        ids.each do |id, file|
          docxml.xpath(ns("//eref[@bibitemid = '#{schema}_#{id}']")).each do |e|
            e["citeas"] = file
            if loc = e.at(ns(".//locality[@type = 'anchor']/referenceFrom"))
              loc.children = "#{id}.#{loc.text}"
            end
          end
          bib = docxml.xpath(ns("//bibitem[@id = '#{schema}_#{id}']")) or next
          docid = bib.at(ns("./docidentifier[@type = 'repository']")) or next
          docid.children = "current-metanorma-collection/#{file}"
          docid.previous = "<docidentifier type='X'>#{file}</docidentifier>"
        end
      end
    end

    # update crossrefences to other documents, to include disambiguating document suffix on id
    def update_anchors(bib, docxml, _id) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      docid = bib&.at(ns("./docidentifier"))&.text
      docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
        if @files[docid]
          (loc = e.at(ns(".//locality[@type = 'anchor']"))) ?
            update_anchor_loc(loc, docid) :
            update_anchor_create_loc(bib, e, docid)
        else
          e << "** Unresolved reference to document #{docid}, id #{e['bibitemid']}"
        end
      end
    end

    def update_anchor_loc(loc, docid)
      document_suffix = Asciidoctor::Standoc::Cleanup.to_ncname(docid)
      ref = loc.at(ns("./referenceFrom")) || return
      anchor = "#{ref.text}_#{document_suffix}"
      return unless @files[docid][:anchors].inject([]) { |m, (_, x)| m+= x.values }.include?(anchor)
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

    # compile and output individual file in collection
    def file_compile(f, filename, identifier)
      # warn "metanorma compile -x html #{f.path}"
      c = Compile.new
      c.compile f.path, { format: :asciidoc, extension_keys: @format }.merge(@compile_options)
      @files[identifier][:outputs] = {}
      @format.each do |e|
        ext = c.processor.output_formats[e]
        fn = File.basename(filename).sub(/(?<=\.)[^\.]+$/, ext.to_s)
        FileUtils.mv f.path.sub(/\.xml$/, ".#{ext}"), File.join(@outdir, fn)
        @files[identifier][:outputs][e] = File.join(@outdir, fn)
      end
    end

    # gather internal bibitem references
    def gather_internal_refs
      @files.each_with_object({}) do |(identifier, x), refs|
        file, _ = targetfile(x, true)
        Nokogiri::XML(file).xpath(ns("//bibitem[@type = 'internal']/docidentifier[@type = 'repository']")).each do |d|
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
      @files.each do |identifier, x|
        file, filename = targetfile(x, true)
        docxml = Nokogiri::XML(file)
        refs.each do |schema, ids|
          ids.keys.each do |id|
            docxml.at(ns("//*[@id = '#{id}'][@type = '#{schema}']")) and
              refs[schema][id] = identifier
          end
        end
      end
      refs.each do |schema, ids|
        ids.each do |id, key|
          key == true and refs[schema][id] = "Missing:#{schema}:#{id}"
        end
      end
      refs
    end

    # process each file in the collection
    # files are held in memory, and altered as postprocessing
    def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      internal_refs = locate_internal_refs
      @files.each do |identifier, x|
        file, filename = targetfile(x, true)
        file = update_xrefs(file, identifier, internal_refs)
        Tempfile.open(["collection", ".xml"], encoding: "utf-8") do |f|
          f.write(file)
          f.close
          file_compile(f, filename, identifier)
        end
      end
    end
  end
end
