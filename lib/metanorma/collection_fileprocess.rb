# frozen_string_literal: true

require "isodoc"
require "metanorma-utils"
require_relative "collection_fileparse"

module Metanorma
  # XML collection renderer
  class CollectionRenderer
    # compile and output individual file in collection
    # warn "metanorma compile -x html #{f.path}"
    def file_compile(file, filename, identifier)
      return if @files.get(identifier, :sectionsplit) == "true"

      opts = {
        format: :asciidoc,
        extension_keys: @format,
        output_dir: @outdir,
      }.merge(compile_options_update(identifier))

      @compile.compile file, opts
      @files.set(identifier, :outputs, {})
      file_compile_formats(filename, identifier)
    end

    def compile_options_update(identifier)
      ret = @compile_options.dup
      Array(@directives).include?("presentation-xml") ||
        @files.get(identifier, :presentationxml) and
        ret.merge!(passthrough_presentation_xml: true)
      @files.get(identifier, :sectionsplit) == "true" and
        ret.merge!(sectionsplit: "true")
      @files.get(identifier, :bare) == true and
        ret.merge!(bare: true)
      ret
    end

    def file_compile_formats(filename, identifier)
      f = @files.get(identifier, :outputs)
      @format << :presentation if @format.include?(:pdf)
      @format.each do |e|
        ext = @compile.processor.output_formats[e]
        fn = File.basename(filename).sub(/(?<=\.)[^.]+$/, ext.to_s)
        (/html$/.match?(ext) && @files.get(identifier, :sectionsplit)) or
          f[e] = File.join(@outdir, fn)
      end
      @files.set(identifier, :outputs, f)
    end

    def copy_file_to_dest(identifier)
      dest = File.join(@outdir, @files.get(identifier, :out_path))
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp @files.get(identifier, :ref), dest
    end

    # process each file in the collection
    # files are held in memory, and altered as postprocessing
    def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      warn "\n\n\n\n\nInternal Refs: #{DateTime.now.strftime('%H:%M:%S')}"
      internal_refs = locate_internal_refs
      @files.keys.each_with_index do |ident, i|
        i.positive? && Array(@directives).include?("bare-after-first") and
          @compile_options.merge!(bare: true)
        if @files.get(ident, :attachment) then copy_file_to_dest(ident)
        else
          file, filename = @files.targetfile_id(ident, read: true)
          warn "\n\n\n\n\nProcess #{filename}: #{DateTime.now.strftime('%H:%M:%S')}"
          collection_xml = update_xrefs(file, ident, internal_refs)
          collection_filename = File.basename(filename, File.extname(filename))
          collection_xml_path = File.join(Dir.tmpdir,
                                          "#{collection_filename}.xml")
          File.write collection_xml_path, collection_xml, encoding: "UTF-8"
          file_compile(collection_xml_path, filename, ident)
          FileUtils.rm(collection_xml_path)
        end
      end
    end

    # gather internal bibitem references
    def gather_internal_refs
      @files.keys.each_with_object({}) do |i, refs|
        @files.get(i, :attachment) and next
        file, = @files.targetfile_id(i, read: true)
        gather_internal_refs1(file, i, refs)
      end
    end

    def gather_internal_refs1(file, ident, refs)
      f = Nokogiri::XML(file, &:huge)
      !@files.get(ident, :sectionsplit) and
        gather_internal_refs_indirect(f, refs)
      key = @files.get(ident, :indirect_key) and
        gather_internal_refs_sectionsplit(f, ident, key, refs)
    end

    def gather_internal_refs_indirect(doc, refs)
      doc.xpath(ns("//bibitem[@type = 'internal']/" \
                   "docidentifier[@type = 'repository']")).each do |d|
                     a = d.text.split(%r{/}, 2)
                     a.size > 1 or next
                     refs[a[0]] ||= {}
                     refs[a[0]][a[1]] = false
                   end
    end

    def gather_internal_refs_sectionsplit(_doc, ident, key, refs)
      refs[key] ||= {}
      @files.get(ident, :ids).each_key do |k|
        refs[key][k] = false
      end
    end

    def populate_internal_refs(refs)
      @files.keys.reject do |k|
        @files.get(k, :attachment) || @files.get(k, :sectionsplit)
      end.each do |ident|
        locate_internal_refs1(refs, ident, @isodoc.docid_prefix("", ident.dup))
      end
      refs
    end

    # resolve file location for the target of each internal reference
    def locate_internal_refs
      refs = populate_internal_refs(gather_internal_refs)
      refs.each do |schema, ids|
        ids.each do |id, key|
          key and next
          refs[schema][id] = "Missing:#{schema}:#{id}"
          @log&.add("Cross-References", nil, refs[schema][id])
        end
      end
      refs
    end

    def locate_internal_refs1(refs, identifier, ident)
      t = locate_internal_refs1_prep(ident)
      refs.each do |schema, ids|
        ids.keys.select { |id| t[id] }.each do |id|
          t[id].at("./ancestor-or-self::*[@type = '#{schema}']") and
            refs[schema][id] = identifier
        end
      end
    end

    def locate_internal_refs1_prep(ident)
      file, = @files.targetfile_id(ident, read: true)
      xml = Nokogiri::XML(file, &:huge)
      r = xml.root["document_suffix"]
      xml.xpath("//*[@id]").each_with_object({}) do |i, x|
        /^semantic_/.match?(i.name) and next
        x[i["id"]] = i
        r and x[i["id"].sub(/_#{r}$/, "")] = i
      end
    end
  end
end
