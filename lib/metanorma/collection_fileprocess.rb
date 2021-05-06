# frozen_string_literal: true

require "isodoc"
require "metanorma-utils"
require_relative "collection_fileparse"

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
        files[identifier] = file_entry(d, path)
        if files[identifier][:attachment]
          files[identifier][:bibdata] = Metanorma::Document
            .attachment_bibitem(identifier).root
        else
          file, _filename = targetfile(files[identifier], true)
          xml = Nokogiri::XML(file)
          add_document_suffix(identifier, xml)
          files[identifier][:anchors] = read_anchors(xml)
          files[identifier][:bibdata] = xml.at(ns("//bibdata"))
        end
      end
      files
    end

    def file_entry(docref, path)
      ret = if docref["fileref"]
              { type: "fileref", ref: File.join(path, docref["fileref"]),
                rel_path: docref["fileref"] }
            else
              { type: "id", ref: docref["id"] }
            end
      ret[:attachment] = docref["attachment"] if docref["attachment"]
      ret
    end

    def add_suffix_to_attributes(doc, suffix, tag_name, attribute_name)
      doc.xpath(ns("//#{tag_name}[@#{attribute_name}]")).each do |elem|
        elem.attributes[attribute_name].value =
          "#{elem.attributes[attribute_name].value}_#{suffix}"
      end
    end

    def add_document_suffix(identifier, doc)
      document_suffix = Metanorma::Utils::to_ncname(identifier)
      [%w[* id], %w[* bibitemid], %w[review from],
       %w[review to], %w[index to], %w[xref target],
       %w[callout target]]
        .each do |(tag_name, attribute_name)|
        add_suffix_to_attributes(doc, document_suffix, tag_name, attribute_name)
      end
    end

    # return file contents + output filename for each file in the collection,
    # given a docref entry
    # @param data [Hash]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def targetfile(data, read = false, doc = true)
      if data[:type] == "fileref" then ref_file data[:ref], read, doc
      else xml_file data[:id], read
      end
    end

    # @param ref [String]
    # @param read [Boolean]
    # @param doc [Boolean]
    # @return [Array<String, nil>]
    def ref_file(ref, read, doc)
      file = File.read(ref, encoding: "utf-8") if read
      filename = ref.dup
      filename.sub!(/\.xml$/, ".html") if doc
      [file, filename]
    end

    # compile and output individual file in collection
    def file_compile(f, filename, identifier)
      # warn "metanorma compile -x html #{f.path}"
      c = Compile.new
      c.compile f.path, { format: :asciidoc,
                          extension_keys: @format }.merge(@compile_options)
      @files[identifier][:outputs] = {}
      @format.each do |e|
        ext = c.processor.output_formats[e]
        fn = File.basename(filename).sub(/(?<=\.)[^\.]+$/, ext.to_s)
        FileUtils.mv f.path.sub(/\.xml$/, ".#{ext}"), File.join(@outdir, fn)
        @files[identifier][:outputs][e] = File.join(@outdir, fn)
      end
    end

    def copy_file_to_dest(fileref)
      _file, filename = targetfile(fileref, true, false)
      dest = File.join(@outdir, fileref[:rel_path])
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp filename, dest
    end

    # process each file in the collection
    # files are held in memory, and altered as postprocessing
    def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      internal_refs = locate_internal_refs
      @files.each do |identifier, x|
        if x[:attachment] then copy_file_to_dest(x)
        else
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
end
