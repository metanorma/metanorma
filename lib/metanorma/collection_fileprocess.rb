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
        unless /html$/.match?(ext) && @files.get(identifier, :sectionsplit)
          f[e] = File.join(@outdir, fn)
        end
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
      @files.keys.each_with_index do |identifier, i|
        i.positive? && Array(@directives).include?("bare-after-first") and
          @compile_options.merge!(bare: true)
        if @files.get(identifier, :attachment)
          copy_file_to_dest(identifier)
        else
          file, filename = @files.targetfile_id(identifier, read: true)
          warn "\n\n\n\n\nProcess #{filename}: #{DateTime.now.strftime('%H:%M:%S')}"
          collection_xml = update_xrefs(file, identifier, internal_refs)
          collection_filename = File.basename(filename, File.extname(filename))
          collection_xml_path = File.join(Dir.tmpdir,
                                          "#{collection_filename}.xml")
          File.write collection_xml_path, collection_xml, encoding: "UTF-8"
          file_compile(collection_xml_path, filename, identifier)
          FileUtils.rm(collection_xml_path)
        end
      end
    end
  end
end
