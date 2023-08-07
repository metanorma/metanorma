require "isodoc"
require "htmlentities"
require "metanorma-utils"

module Metanorma
  # XML collection renderer
  class FileLookup
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
      read_files
    end

    def read_files
      @xml.xpath(ns("//docref")).each { |d| read_file(d) }
      add_section_split
    end

    def read_file(docref)
      ident = docref.at(ns("./identifier"))
      i = key(@isodoc.docid_prefix(ident["type"], ident.children.to_xml))
      entry = file_entry(docref, ident.children.to_xml)
      bibdata_process(entry, i)
      bibitem_process(entry)
      @files[i] = entry
    end

    def bibdata_process(entry, identifier)
      if entry[:attachment]
        entry[:bibdata] = Metanorma::Document
          .attachment_bibitem(identifier).root
      else
        file, _filename = targetfile(entry, read: true)
        xml = Nokogiri::XML(file)
        add_document_suffix(identifier, xml)
        entry[:anchors] = read_anchors(xml)
        entry[:bibdata] = xml.at(ns("//bibdata"))
      end
    end

    def bibitem_process(entry)
      entry[:bibitem] = entry[:bibdata].dup
      entry[:bibitem].name = "bibitem"
      entry[:bibitem]["hidden"] = "true"
      entry[:bibitem].at("./*[local-name() = 'ext']")&.remove
    end

    def add_section_split
        #require "debug"; binding.b
      ret = @files.keys.each_with_object({}) do |k, m|
        if @files[k][:sectionsplit] == "true" && !@files[k]["attachment"]
          s, manifest = sectionsplit(@files[k][:ref])
          s.each_with_index do |f1, i|
            add_section_split_instance(f1, m, k, i)
          end
          m["#{k}:index.html"] = add_section_split_cover(manifest, k)
        end
        m[k] = @files[k]
        #require "debug"; binding.b
      end
      @files = ret
    end

    def add_section_split_cover(manifest, ident)
      cover = section_split_cover(manifest, @parent.dir_name_cleanse(ident))
      @files[ident][:out_path] = cover
      { attachment: true, index: false, out_path: cover,
        ref: File.join(File.dirname(manifest.file), cover) }
    end

    def section_split_cover(col, ident)
      dir = File.dirname(col.file)
      @compile.collection_setup(nil, dir)
      #require "debug";binding.b
      CollectionRenderer.new(col, dir,
                             output_folder: "#{ident}_collection",
                             format: %i(html),
                             coverpage: File.join(dir, "cover.html")).coverpage
      FileUtils.mv "#{ident}_collection/index.html",
                   File.join(dir, "#{ident}_index.html")
      FileUtils.rm_rf "#{ident}_collection"
      "#{ident}_index.html"
    end

    def add_section_split_instance(file, manifest, key, idx)
      presfile = File.join(File.dirname(@files[key][:ref]),
                           File.basename(file[:url]))
      newkey = key("#{key.strip} #{file[:title]}")
      manifest[newkey] =
        { parentid: key, presentationxml: true, type: "fileref",
          rel_path: file[:url], out_path: File.basename(file[:url]),
          anchors: read_anchors(Nokogiri::XML(File.read(presfile))),
          bibdata: @files[key][:bibdata], ref: presfile }
      manifest[newkey][:bare] = true unless idx.zero?
    end

    def sectionsplit(file)
      #require "debug"; binding.b
      @compile.compile(
        file, { format: :asciidoc, extension_keys: [:presentation] }
        .merge(@parent.compile_options)
      )
      r = file.sub(/\.xml$/, ".presentation.xml")
      xml = Nokogiri::XML(File.read(r))
      s = @compile.sectionsplit(xml, File.basename(r), File.dirname(r))
        .sort_by { |f| f[:order] }
      [s, @compile.collection_manifest(File.basename(r), s, xml, nil,
                                       File.dirname(r))]
    end

    # rel_path is the source file address, determined relative to the YAML.
    # out_path is the destination file address, with any references outside
    # the working directory (../../...) truncated
    # identifier is the id with only spaces, no nbsp
    def file_entry(ref, identifier)
      out = ref["attachment"] ? ref["fileref"] : File.basename(ref["fileref"])
      ret = if ref["fileref"]
              { type: "fileref", ref: @documents[identifier].file,
                rel_path: ref["fileref"], out_path: out }
            else { type: "id", ref: ref["id"] } end
      %w(attachment sectionsplit index presentation-xml
         bare-after-first).each do |s|
        ret[s.gsub("-", "").to_sym] = ref[s] if ref[s]
      end
      ret.compact
    end

    def add_suffix_to_attributes(doc, suffix, tag_name, attribute_name)
      doc.xpath(ns("//#{tag_name}[@#{attribute_name}]")).each do |elem|
        elem.attributes[attribute_name].value =
          "#{elem.attributes[attribute_name].value}_#{suffix}"
      end
    end

    def add_document_suffix(identifier, doc)
      document_suffix = Metanorma::Utils::to_ncname(identifier)
      Metanorma::Utils::anchor_attributes.each do |(tag_name, attribute_name)|
        add_suffix_to_attributes(doc, document_suffix, tag_name, attribute_name)
      end
      url_in_css_styles(doc, document_suffix)
    end

    # update relative URLs, url(#...), in CSS in @style attrs (including SVG)
    def url_in_css_styles(doc, document_suffix)
      doc.xpath("//*[@style]").each do |s|
        s["style"] = s["style"]
          .gsub(%r{url\(#([^)]+)\)}, "url(#\\1_#{document_suffix})")
      end
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

    def key(ident)
      @c.decode(ident).gsub(/(\s|[ ])+/, " ")
    end

    def keys
      @files.keys
    end

    def get(ident, attr = nil)
      if attr
        @files[key(ident)][attr]
      else
        @files[key(ident)]
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
