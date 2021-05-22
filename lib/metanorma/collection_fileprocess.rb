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
        files[identifier] = file_entry(d, identifier, path)
        if files[identifier][:attachment]
          files[identifier][:bibdata] = Metanorma::Document
            .attachment_bibitem(identifier).root
        else
          file, _filename = targetfile(files[identifier], read: true)
          xml = Nokogiri::XML(file)
          add_document_suffix(identifier, xml)
          files[identifier][:anchors] = read_anchors(xml)
          files[identifier][:bibdata] = xml.at(ns("//bibdata"))
        end
      end
      files
    end

    # rel_path is the source file address, determined relative to the YAML.
    # out_path is the destination file address, with any references outside
    # the working directory (../../...) truncated
    def file_entry(docref, identifier, _path)
      ret = if docref["fileref"]
              { type: "fileref", ref: @documents[identifier].file,
                rel_path: docref["fileref"],
                out_path: Util::source2dest_filename(docref["fileref"]) }
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
    # @param data [Hash] docref entry
    # @param read [Boolean] read the file in and return it
    # @param doc [Boolean] I am a Metanorma document,
    # so my URL should end with html or pdf or whatever
    # @param relative [Boolean] Return output path,
    # formed relative to YAML file, not input path, relative to calling function
    # @return [Array<String, nil>]
    def targetfile(data, options)
      options = { read: false, doc: true, relative: false }.merge(options)
      path = options[:relative] ? data[:out_path] : data[:ref]
      if data[:type] == "fileref"
        ref_file path, options[:read], options[:doc]
      else
        xml_file data[:id], options[:read]
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
    def file_compile(file, filename, identifier)
      # warn "metanorma compile -x html #{f.path}"
      c = Compile.new
      c.compile file.path, { format: :asciidoc,
                             extension_keys: @format }.merge(@compile_options)
      @files[identifier][:outputs] = {}
      @format.each do |e|
        ext = c.processor.output_formats[e]
        fn = File.basename(filename).sub(/(?<=\.)[^\.]+$/, ext.to_s)
        FileUtils.mv file.path.sub(/\.xml$/, ".#{ext}"), File.join(@outdir, fn)
        @files[identifier][:outputs][e] = File.join(@outdir, fn)
      end
    end

    def copy_file_to_dest(fileref)
      _file, filename = targetfile(fileref, read: true, doc: false)
      dest = File.join(@outdir, fileref[:out_path])
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
          file, filename = targetfile(x, read: true)
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
