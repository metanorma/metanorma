# frozen_string_literal: true

require "isodoc"
require "metanorma-utils"
require_relative "fileparse"

module Metanorma
  class Collection
    class Renderer
      # compile and output individual file in collection
      # warn "metanorma compile -x html #{f.path}"
      def file_compile(file, filename, identifier)
        @files.get(identifier, :sectionsplit) and return
        opts = {
          format: :asciidoc,
          extension_keys: @files.get(identifier, :format),
          output_dir: @outdir,
          type: @flavor,
        }.merge(compile_options_update(identifier))
        @compile.compile file, opts
        @files.set(identifier, :outputs, {})
        file_compile_formats(filename, identifier, opts)
      end

      def compile_options_update(identifier)
        ret = @compile_options.dup
        @directives.detect { |d| d.key == "presentation-xml" } ||
          @files.get(identifier, :presentationxml) and
          ret.merge!(passthrough_presentation_xml: true)
        @files.get(identifier, :sectionsplit) == true and
          ret.merge!(sectionsplit: true)
        @files.get(identifier, :bare) == true and
          ret.merge!(bare: true)
        ret
      end

      #       def allowed_extension_keys
      #         ret = @format.dup
      #         @directives.detect { |d| d.key == "individual-pdf" } or
      #           ret.delete(:pdf)
      #         @directives.detect { |d| d.key == "individual-doc" } or
      #           ret.delete(:doc)
      #         ret
      #       end

      def file_compile_formats(filename, identifier, opts)
        f = @files.get(identifier, :outputs)
        format = opts[:extension_keys]
        concatenate_presentation?({ format: format }) and format << :presentation
        format.each do |e|
          file_compile_format(filename, identifier, e, f)
        end
        @files.set(identifier, :outputs, f)
      end

      def file_compile_format(filename, identifier, format, output_formats)
        ext = @compile.processor.output_formats[format]
        fn = File.basename(filename).sub(/(?<=\.)[^.]+$/, ext.to_s)
        (/html$/.match?(ext) && @files.get(identifier, :sectionsplit)) or
          output_formats[format] = File.join(@outdir, fn)
      end

      def copy_file_to_dest(identifier)
        out = Pathname.new(@files.get(identifier, :out_path)).cleanpath
        out.absolute? and
          out = out.relative_path_from(File.expand_path(FileUtils.pwd))
        dest = File.join(@outdir, @disambig.source2dest_filename(out.to_s))
        FileUtils.mkdir_p(File.dirname(dest))
        source = @files.get(identifier, :ref)
        source != dest and FileUtils.cp_r source, dest, remove_destination: true
      end

      # process each file in the collection
      # files are held in memory, and altered as postprocessing
      def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        warn "\n\n\n\n\nRender Files: #{DateTime.now.strftime('%H:%M:%S')}"
        internal_refs = locate_internal_refs
        @files.keys.each_with_index do |ident, i|
          i.positive? && @directives.detect do |d|
            d.key == "bare-after-first"
          end and
            @compile_options.merge!(bare: true)
          if @files.get(ident, :attachment) then copy_file_to_dest(ident)
          else
            file, fname = @files.targetfile_id(ident, read: true)
            warn "\n\n\n\n\nProcess #{fname}: #{DateTime.now.strftime('%H:%M:%S')}"
            collection_xml = update_xrefs(file, ident, internal_refs)
            collection_filename = File.basename(fname, File.extname(fname))
            collection_xml_path = File.join(Dir.tmpdir,
                                            "#{collection_filename}.xml")
            File.write collection_xml_path, collection_xml, encoding: "UTF-8"
            file_compile(collection_xml_path, fname, ident)
            FileUtils.rm(collection_xml_path)
          end
        end
      end

      # gather internal bibitem references
      def gather_internal_refs
        @files.keys.each_with_object({}) do |i, refs|
          @files.get(i, :attachment) and next
          @files.get(i, :sectionsplit) and next
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
          locate_internal_refs1(refs, ident,
                                @isodoc.docid_prefix("", ident.dup))
        end
        refs
      end

      # resolve file location for the target of each internal reference
      def locate_internal_refs
        warn "\n\n\n\n\nInternal Refs: #{DateTime.now.strftime('%H:%M:%S')}"
        refs = populate_internal_refs(gather_internal_refs)
        refs.each do |schema, ids|
          ids.each do |id, key|
            key and next
            refs[schema][id] = "Missing:#{schema}:#{id}"
            @log&.add("METANORMA_1", nil, params: [refs[schema][id]])
          end
        end
        refs
      end

      def locate_internal_refs1(refs, identifier, ident)
        file, = @files.targetfile_id(ident, read: true)
        t = locate_internal_refs1_prep(file)
        refs.each do |schema, ids|
          ids.keys.select { |id| t[id] }.each do |id|
            t[id].at("./ancestor-or-self::*[@type = '#{schema}']") and
              refs[schema][id] = identifier
          end
        end
      end

      def locate_internal_refs1_prep(file)
        xml = Nokogiri::XML(file, &:huge)
        r = xml.root["document_suffix"]
        xml.xpath("//*[@id]").each_with_object({}) do |i, x|
          /^semantic_/.match?(i.name) and next
          x[i["id"]] = i
          r and x[i["id"].sub(/_#{r}$/, "")] = i
        end
      end

      def update_bibitem(bib, identifier)
        docid = get_bibitem_docid(bib, identifier) or return
        newbib = dup_bibitem(docid, bib)
        url = @files.url(docid, relative: true,
                                doc: !@files.get(docid, :attachment))
        dest = newbib.at("./docidentifier") || newbib.at(ns("./docidentifier"))
        dest or dest = newbib.elements[-1]
        dest.previous = "<uri type='citation'>#{url}</uri>"
        bib.replace(newbib)
      end
    end
  end
end
