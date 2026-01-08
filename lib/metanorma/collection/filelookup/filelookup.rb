require "isodoc"
require "htmlentities"
require "metanorma-utils"
require_relative "filelookup_sectionsplit"

module Metanorma
  class Collection
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
        @isodoc_presxml = parent.isodoc_presxml
        @path = path
        @compile = parent.compile
        @documents = parent.documents
        @files_to_delete = []
        @disambig = Util::DisambigFiles.new
        @manifest = parent.manifest
        read_files(@manifest.entry, parent.manifest)
      end

      def read_files(entries, parent)
        Array(entries).each do |e|
          derive_format(e, parent)
          e.file and read_file(e)
          read_files(e.entry, e)
        end
      end

      def derive_format(entry, parent)
        entry.attachment and return
        entry.format ||= parent.format || %w(xml presentation html)
        entry.format |= ["xml", "presentation"]
      end

      def read_file(manifest)
        i, k = read_file_idents(manifest)
        entry = file_entry(manifest, k) or return
        bibdata_process(entry, i)
        bibitem_process(entry)
        @files[key(i)] = entry
      end

      def read_file_idents(manifest)
        id = manifest.identifier
        sanitised_id = key(@isodoc.docid_prefix("", manifest.identifier.dup))
        #       if manifest.bibdata and # NO, DO NOT FISH FOR THE GENUINE IDENTIFIER IN BIBDATA
        #         d = manifest.bibdata.docidentifier.detect { |x| x.primary } ||
        #           manifest.bibdata.docidentifier.first
        #         k = d.id
        #         i = key(@isodoc.docid_prefix(d.type, d.id.dup))
        #       end
        [id, sanitised_id]
      end

      def bibdata_process(entry, ident)
        if entry[:attachment]
          entry[:bibdata] =
            Metanorma::Collection::Document.attachment_bibitem(ident).root
        else
          file, _filename = targetfile(entry, read: true)
          xml = Nokogiri::XML(file, &:huge)
          add_document_suffix(ident, xml)
          entry.merge!(bibdata_extract(xml))
        end
      end

      def anchors_lookup(anchors)
        anchors.values.each_with_object({}) do |v, m|
          v.each_value { |v1| m[v1] = true }
        end
      end

      def bibdata_extract(xml)
        anchors = read_anchors(xml)
        { anchors: anchors, anchors_lookup: anchors_lookup(anchors),
          ids: read_ids(xml),
          bibdata: xml.at(ns("//bibdata")),
          document_suffix: xml.root["document_suffix"] }
      end

      def bibitem_process(entry)
        entry[:bibitem] = entry[:bibdata].dup
        entry[:bibitem].name = "bibitem"
        entry[:bibitem]["hidden"] = "true"
        entry[:bibitem].at("./*[local-name() = 'ext']")&.remove
      end

      def file_entry(ref, identifier)
        ref.file or return
        abs = @documents[Util::key identifier].file
        ret = if ref.file then file_entry_struct(ref, abs)
              else { type: "id", ref: ref.id }
              end
        file_entry_copy(ref, ret)
        ret.compact
      end

      # ref is the absolute source file address
      # rel_path is the relative source file address, relative to the YAML location
      # out_path is the destination file address, with any references outside
      # the working directory (../../...) truncated, and based on relative path
      # identifier is the id with only spaces, no nbsp
      # extract_opts are the compilation options extracted as document attributes
      def file_entry_struct(ref, abs)
        adoc = abs.sub(/\.xml$/, ".adoc")
        if File.exist?(adoc)
          opts = Metanorma::Input::Asciidoc.new.extract_options(File.read(adoc))
        end
        { type: "fileref", ref: abs, rel_path: ref.file, url: ref.url,
          out_path: output_file_path(ref), pdffile: ref.pdffile,
          format: ref.format&.map(&:to_sym), extract_opts: opts }.compact
      end

      # TODO make the output file location reflect source location universally,
      # not just for attachments: no File.basename
      def output_file_path(ref)
        f = File.basename(ref.file)
        ref.attachment and f = ref.file
        @disambig.source2dest_filename(f)
      end

      def file_entry_copy(ref, ret)
        %w(attachment sectionsplit index presentation-xml url
           bare-after-first).each do |s|
          ref.respond_to?(s.to_sym) and
            ret[s.delete("-").to_sym] = ref.send(s)
        end
      end

      def add_document_suffix(identifier, doc)
        document_suffix = Metanorma::Utils::to_ncname(identifier)
        Util::anchor_id_attributes.each do |(tag_name, attr_name)|
          Util::add_suffix_to_attrs(doc, document_suffix, tag_name, attr_name,
                                    @isodoc)
        end
        url_in_css_styles(doc, document_suffix)
        doc.root["document_suffix"] ||= ""
        doc.root["document_suffix"] += document_suffix
      end

      # update relative URLs, url(#...), in CSS in @style attrs (including SVG)
      def url_in_css_styles(doc, document_suffix)
        doc.xpath("//*[@style]").each do |s|
          s["style"] = s["style"]
            .gsub(%r{url\(#([^()]+)\)}, "url(#\\1_#{document_suffix})")
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
                else val[:label].gsub(%r{<[^>]+>}, "")
                end
        ret[val[:type]][index] = key
        v = val[:value] and ret[val[:type]][v.gsub(%r{<[^>]+>}, "")] = key
      end

      # Also parse all ids in doc (including ones which won't be xref targets)
      def read_ids(xml)
        ret = {}
        xml.traverse do |x|
          x.text? and next
          x["id"] and ret[x["id"]] = true
        end
        ret
      end

      def key(ident)
        @c.decode(ident).gsub(/(\p{Zs})+/, " ")
          .sub(/^metanorma-collection /, "")
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
end
