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
        identifier = d.at(ns("./identifier")).children.to_xml
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
        files[identifier][:bibitem] = files[identifier][:bibdata].dup
        files[identifier][:bibitem].name = "bibitem"
        files[identifier][:bibitem]["hidden"] = "true"
        files[identifier][:bibitem]&.at("./*[local-name() = 'ext']")&.remove
      end
      add_section_split(files)
    end

    def add_section_split(files)
      files.keys.each_with_object({}) do |k, m|
        if files[k][:sectionsplit] == "true" && !files[k]["attachment"]
          sectionsplit(files[k][:ref]).each_with_index do |f1, i|
            add_section_split_instance(f1, m, k, i, files)
          end
        end
        m[k] = files[k]
      end
    end

    def add_section_split_instance(file, manifest, key, idx, files)
      dir = File.dirname(files[key][:ref])
      presfile = File.join(dir, File.basename(file[:url]))
      manifest[key + file[:title]] =
        { parentid: key, presentationxml: true, type: "fileref",
          rel_path: file[:url], out_path: File.basename(file[:url]),
          anchors: read_anchors(Nokogiri::XML(File.read(presfile))),
          bibdata: files[key][:bibdata], ref: presfile }
      manifest[key + file[:title]][:bare] = true unless idx.zero?
    end

    def sectionsplit(file)
      @compile.compile(
        file, { format: :asciidoc, extension_keys: [:presentation] }
        .merge(@compile_options)
      )
      r = file.sub(/\.xml$/, ".presentation.xml")
      @compile.sectionsplit(
        Nokogiri::XML(File.read(r)), File.basename(r), File.dirname(r),
      ).sort_by { |f| f[:order] }
    end

    # rel_path is the source file address, determined relative to the YAML.
    # out_path is the destination file address, with any references outside
    # the working directory (../../...) truncated
    def file_entry(ref, identifier, _path)
      out = ref["attachment"] ? ref["fileref"] : File.basename(ref["fileref"])
      ret = if ref["fileref"]
              { type: "fileref", ref: @documents[identifier].file,
                rel_path: ref["fileref"],
                out_path: out }
            else
              { type: "id", ref: ref["id"] }
            end
      ret[:attachment] = ref["attachment"] if ref["attachment"]
      ret[:sectionsplit] = ref["sectionsplit"] if ref["sectionsplit"]
      ret[:presentationxml] = ref["presentation-xml"] if ref["presentation-xml"]
      ret[:bareafterfirst] = ref["bare-after-first"] if ref["bare-after-first"]
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
      path = options[:relative] ? data[:rel_path] : data[:ref]
      if data[:type] == "fileref"
        ref_file path, data[:out_path], options[:read], options[:doc]
      else
        xml_file data[:id], options[:read]
      end
    end

    # @param ref [String]
    # @param read [Boolean]
    # @param doc [Boolean]
    # @return [Array<String, nil>]
    def ref_file(ref, out, read, doc)
      file = File.read(ref, encoding: "utf-8") if read
      filename = out.dup
      filename.sub!(/\.xml$/, ".html") if doc
      [file, filename]
    end

    # compile and output individual file in collection
    # warn "metanorma compile -x html #{f.path}"
    def file_compile(file, filename, identifier)
      @compile.compile file.path, { format: :asciidoc, extension_keys: @format }
        .merge(compile_options(identifier))
      @files[identifier][:outputs] = {}
      file_compile_formats(file, filename, identifier)
    end

    def compile_options(identifier)
      ret = @compile_options.dup
      Array(@directives).include?("presentation-xml") ||
        @files[identifier][:presentationxml] and
        ret.merge!(passthrough_presentation_xml: true)
      @files[identifier][:sectionsplit] == "true" and
        ret.merge!(sectionsplit: "true")
      @files[identifier][:bare] == true and
        ret.merge!(bare: true)
      ret
    end

    def file_compile_formats(file, filename, identifier)
      @format.each do |e|
        ext = @compile.processor.output_formats[e]
        fn = File.basename(filename).sub(/(?<=\.)[^.]+$/, ext.to_s)
        if /html$/.match?(ext) && @files[identifier][:sectionsplit]
          # file_sectionsplit_copy(file, fn, identifier, ext, e)
        else
          FileUtils.cp file.path.sub(/\.xml$/, ".#{ext}"),
                       File.join(@outdir, fn)
          @files[identifier][:outputs][e] = File.join(@outdir, fn)
        end
      end
    end

    def file_sectionsplit_copy(file, base, identifier, ext, format)
      dir = file.path.sub(/\.xml$/, ".#{ext}_collection")
      files = Dir.glob("#{dir}/*.#{ext}")
      FileUtils.cp files, @outdir
      cover = File.join(@outdir, base.sub(/\.html$/, ".index.html"))
      FileUtils.cp File.join(dir, "index.html"), cover
      @files[identifier][:outputs][format] = cover
    end

    def copy_file_to_dest(fileref)
      dest = File.join(@outdir, fileref[:out_path])
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp fileref[:ref], dest
    end

    # process each file in the collection
    # files are held in memory, and altered as postprocessing
    def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
            warn "\n\n\n\n\nInternal Refs: #{DateTime.now.strftime('%H:%M:%S')}"
      internal_refs = locate_internal_refs
      @files.each_with_index do |(identifier, x), i|
        i.positive? && Array(@directives).include?("bare-after-first") and
          @compile_options.merge!(bare: true)
        if x[:attachment] then copy_file_to_dest(x)
        else
          file, filename = targetfile(x, read: true)
            warn "\n\n\n\n\nProcess #{filename}: #{DateTime.now.strftime('%H:%M:%S')}"
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
