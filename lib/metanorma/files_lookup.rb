require "isodoc"
require "htmlentities"
require "metanorma-utils"
require_relative "files_lookup_sectionsplit"

module Metanorma
  # XML collection renderer
  class FileLookup
    attr_accessor :files_to_delete, :parent

    # hash for each document in collection of document identifier to:
    # document reference (fileref or id), type of document reference,
    # and bibdata entry for that file
    # @param path [String] path to collection
    def initialize(path, parent)
      @c = HTMLEntities.new
      @files = {}
      @parent = parent
      @xml = parent.xml
      @isodoc = parent.isodoc
      @path = path
      @compile = parent.compile
      @documents = parent.documents
      @files_to_delete = []
      @disambig = Util::DisambigFiles.new
      @manifest = parent.manifest
      read_files(@manifest.entry)
    end

    def read_files # KILL
      @disambig = Util::DisambigFiles.new
      @xml.xpath(ns("//docref")).each { |d| read_file(d) }
    end

    def read_files(entries)
      Array(entries).each do |e|
        e.file and read_file(e)
        read_files(e.entry)
      end
    end

    def read_file(docref) # KILL
      ident = docref.at(ns("./identifier"))
      i = key(@isodoc.docid_prefix(ident["type"], ident.children.to_xml))
      entry = file_entry(docref, ident.children.to_xml) or return
      bibdata_process(entry, i)
      bibitem_process(entry)
      @files[i] = entry
    end

    def read_file(manifest)
      i = @isodoc.docid_prefix("", manifest.identifier)
      k = manifest.identifier
      if false && manifest.bibdata and # NO, DO NOT FISH FOR THE GENUINE IDENTIFIER IN BIBDATA
        d = manifest.bibdata.docidentifier.detect { |x| x.primary } ||
          manifest.bibdata.docidentifier.first
        k = d.id
        i = key(@isodoc.docid_prefix(d.type, d.id))
      end
      entry = file_entry(manifest, k) or return
      bibdata_process(entry, i)
      bibitem_process(entry)
      @files[key(i)] = entry
    end

    def bibdata_process(entry, ident)
      if entry[:attachment]
        entry[:bibdata] = Metanorma::Document.attachment_bibitem(ident).root
      else
        file, _filename = targetfile(entry, read: true)
        xml = Nokogiri::XML(file, &:huge)
        add_document_suffix(ident, xml)
        entry.merge!(anchors: read_anchors(xml), ids: read_ids(xml),
                     bibdata: xml.at(ns("//bibdata")),
                     document_suffix: xml.root["document_suffix"])
      end
    end

    def bibitem_process(entry)
      entry[:bibitem] = entry[:bibdata].dup
      entry[:bibitem].name = "bibitem"
      entry[:bibitem]["hidden"] = "true"
      entry[:bibitem].at("./*[local-name() = 'ext']")&.remove
    end

    # ref is the absolute source file address
    # rel_path is the relative source file address, determined relative to the YAML.
    # out_path is the destination file address, with any references outside
    # the working directory (../../...) truncated, and based on relative path
    # identifier is the id with only spaces, no nbsp
    def file_entry(ref, identifier) # KILL
      ref["fileref"] or return
      ref["absolute_location"] = @documents[Util::key identifier].file
      ret = if ref["fileref"]
              { type: "fileref", ref: ref["absolute_location"],
                rel_path: ref["fileref"], url: ref["url"],
                out_path: output_file_path(ref) }
            else { type: "id", ref: ref["id"] }
            end
      file_entry_copy(ref, ret)
      warn ret
      ret.compact
    end

    def file_entry(ref, identifier)
      ref.file or return
      abs = @documents[Util::key identifier].file
      ret = if ref.file
              { type: "fileref", ref: abs,
                rel_path: ref.file, url: ref.url,
                out_path: output_file_path(ref) }
            else { type: "id", ref: ref.id }
            end
      file_entry_copy(ref, ret)
      warn ret
      ret.compact
    end

    # TODO make the output file location reflect source location universally,
    # not just for attachments: no File.basename
    def output_file_path(ref) # KILL
      f = File.basename(ref["fileref"])
      ref["attachment"] and f = ref["fileref"]
      @disambig.source2dest_filename(f)
    end

    def output_file_path(ref)
      f = File.basename(ref.file)
      ref.attachment and f = ref.file
      @disambig.source2dest_filename(f)
    end

    def file_entry_copy(ref, ret) # KILL
      %w(attachment sectionsplit index presentation-xml url
         bare-after-first).each do |s|
        ret[s.gsub("-", "").to_sym] = ref[s] if ref[s]
      end
    end

    def file_entry_copy(ref, ret)
      %w(attachment sectionsplit index presentation-xml url
         bare-after-first).each do |s|
           ref.respond_to?(s.to_sym) and
             ret[s.gsub("-", "").to_sym] = ref.send(s)
      end
    end

    def add_document_suffix(identifier, doc)
      document_suffix = Metanorma::Utils::to_ncname(identifier)
      Metanorma::Utils::anchor_attributes.each do |(tag_name, attribute_name)|
        Util::add_suffix_to_attributes(doc, document_suffix, tag_name,
                                       attribute_name, @isodoc)
      end
      url_in_css_styles(doc, document_suffix)
      doc.root["document_suffix"] ||= ""
      doc.root["document_suffix"] += document_suffix
    end

    # update relative URLs, url(#...), in CSS in @style attrs (including SVG)
    def url_in_css_styles(doc, document_suffix)
      doc.xpath("//*[@style]").each do |s|
        s["style"] = s["style"]
          .gsub(%r{url\(#([^)]+)\)}, "url(#\\1_#{document_suffix})")
      end
    end

    # return citation url for file
    # @param doc [Boolean] I am a Metanorma document,
    # so my URL should end with html or pdf or whatever
    def url(ident, options)
      data = get(ident)
      data[:url] || targetfile(data, options)[1]
    end

    # are references to the file to be linked to a file in the collection,
    # or externally? Determines whether file suffix anchors are to be used
    def url?(ident)
      data = get(ident) or return false
      data[:url]
    end

    # return file contents + output filename for each file in the collection,
    # given a docref entry
    # @param data [Hash] docref entry
    # @param read [Boolean] read the file in and return it
    # @param doc [Boolean] I am a Metanorma document,
    # so my URL should end with html or pdf or whatever
    # @param relative [Boolean] Return output path,
    # formed relative to YAML file, not input path, relative to calling function
    # @return [Array<String, nil>]
    def targetfile(data, options)
      options = { read: false, doc: true, relative: false }.merge(options)
      path = options[:relative] ? data[:rel_path] : data[:ref]
      if data[:type] == "fileref"
        ref_file path, data[:out_path], options[:read], options[:doc]
      else
        xml_file data[:id], options[:read]
      end
    end

    def targetfile_id(ident, options)
      targetfile(get(ident), options)
    end

    def ref_file(ref, out, read, doc)
      file = File.read(ref, encoding: "utf-8") if read
      filename = out.dup
      filename.sub!(/\.xml$/, ".html") if doc
      [file, filename]
    end

    def xml_file(id, read)
      file = @xml.at(ns("//doc-container[@id = '#{id}']")).to_xml if read
      filename = "#{id}.html"
      [file, filename]
    end

    # map locality type and label (e.g. "clause" "1") to id = anchor for
    # a document
    # Note: will only key clauses, which have unambiguous reference label in
    # locality. Notes, examples etc with containers are just plunked against
    # UUIDs, so that their IDs can at least be registered to be tracked
    # as existing.
    def read_anchors(xml)
      xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.i18n,
                                { locale: @locale })
      xrefs.parse xml
      xrefs.get.each_with_object({}) do |(k, v), ret|
        read_anchors1(k, v, ret)
      end
    end

    def read_anchors1(key, val, ret)
      val[:type] ||= "clause"
      ret[val[:type]] ||= {}
      index = if val[:container] || val[:label].nil? || val[:label].empty?
                UUIDTools::UUID.random_create.to_s
              else val[:label]
              end
      ret[val[:type]][index] = key
      ret[val[:type]][val[:value]] = key if val[:value]
    end

    # Also parse all ids in doc (including ones which won't be xref targets)
    def read_ids(xml)
      ret = {}
      xml.traverse do |x|
        x.text? and next
        /^semantic__/.match?(x.name) and next
        x["id"] and ret[x["id"]] = true
      end
      ret
    end

    def key(ident)
      @c.decode(ident).gsub(/(\p{Zs})+/, " ").sub(/^metanorma-collection /, "")
    end

    def keys
      @files.keys
    end

    def get(ident, attr = nil)
      if attr then @files[key(ident)][attr]
      else @files[key(ident)]
      end
    end

    def set(ident, attr, value)
      @files[key(ident)][attr] = value
    end

    def each
      @files.each
    end

    def each_with_index
      @files.each_with_index
    end

    def ns(xpath)
      @isodoc.ns(xpath)
    end
  end
end
