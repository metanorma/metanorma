require_relative "../sectionsplit/sectionsplit"
# require "concurrent-ruby"

module Metanorma
  class Collection
    class FileLookup
      def add_section_split
        ret = @files.keys.each_with_object({}) do |k, m|
          if @files[k][:sectionsplit] && !@files[k][:attachment]
            original_out_path = process_section_split_instance(k, m)
            cleanup_section_split_instance(k, m, original_out_path)
          end
          m[k] = @files[k]
        end
        @files = ret
      end

      def process_section_split_instance(key, manifest)
        # Save the original out_path before it gets modified
        original_out_path = @files[key][:out_path]
        s, sectionsplit_manifest = sectionsplit(key)
        # section_split_instance_threads(s, manifest, key)
        s.each_with_index do |f1, i|
          add_section_split_instance(f1, manifest, key, i)
        end
        a = add_section_split_attachments(sectionsplit_manifest, key) and
          manifest["#{key}:attachments"] = a
        add_section_split_cover(manifest, sectionsplit_manifest, key)
        # Return the original path for cleanup
        original_out_path
      end

      def section_split_instance_threads(s, manifest, key)
        @mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(4)
        s.each_with_index do |f1, i|
          pool.post do
            add_section_split_instance(f1, manifest, key, i)
          end
        end
        pool.shutdown
        pool.wait_for_termination
      end

      def cleanup_section_split_instance(key, manifest, original_out_path)
        # Delete the sectionsplit index.html from source directory after it's copied to output
        @files_to_delete << manifest["#{key}:index.html"][:ref]
        # Delete the original files when sectionsplit happens (all formats: html, xml, presentation.xml)
        # Use the saved original out_path (before it was changed to index.html)
        if original_out_path
          base = File.join(@parent.outdir, original_out_path.sub(/\.xml$/, ""))
          @files_to_delete << "#{base}.html"
          @files_to_delete << "#{base}.xml"
          @files_to_delete << "#{base}.presentation.xml"
        end
        # @files[key].delete(:ids).delete(:anchors)
        @files[key][:indirect_key] = @sectionsplit.key
      end

      def add_section_split_cover(manifest, sectionsplit_manifest, ident)
        cover = @sectionsplit
          .section_split_cover(sectionsplit_manifest,
                               @parent.dir_name_cleanse(ident),
                               one_doc_collection?)
        @files[ident][:out_path] = cover
        src = File.join(File.dirname(sectionsplit_manifest.file), cover)
        m = { attachment: true, index: false, out_path: cover, ref: src }
        manifest["#{ident}:index.html"] = m
        one_doc_collection? and
          add_cover_one_doc_coll(manifest, sectionsplit_manifest, ident, m)
      end

      def add_cover_one_doc_coll(manifest, sectionsplit_manifest, key, entry)
        idx = File.join(File.dirname(sectionsplit_manifest.file), "index.html")
        FileUtils.cp entry[:ref], idx
        manifest["#{key}:index1.html"] =
          entry.merge(out_path: "index.html", ref: idx)
      end

      def one_doc_collection?
        docs = 0
        @files.each_value do |v|
          v[:attachment] and next
          v[:presentationxml] and next
          docs += 1
        end
        docs <= 1
      end

      def add_section_split_attachments(manifest, ident)
        attachments = @sectionsplit
          .section_split_attachments(out: File.dirname(manifest.file))
        attachments or return
        @files[ident][:out_path] = attachments
        { attachment: true, index: false, out_path: attachments,
          ref: File.join(File.dirname(manifest.file), attachments) }
      end

      def add_section_split_instance(file, manifest, key, idx)
        presfile, newkey, xml = add_section_split_instance_prep(file, key)
        anchors = read_anchors(xml)
        # Preserve directory structure in out_path if parent has custom sectionsplit_filename with directory
        sectionsplit_fname = @files[key][:sectionsplit_filename]

        # file[:url] from sectionsplit.rb should contain full path (from output_filename)
        # but due to how file is passed around, we need to recompute from the actual split filename
        # The file title gives us the computed filename from sectionsplit
        # Extract just the base filename without extension
        base_filename = File.basename(file[:url], ".xml")

        # If sectionsplit pattern has directory, prepend it
        out_path_value = if sectionsplit_fname && File.dirname(sectionsplit_fname) != "."
                           # Pattern has directory - use it
                           File.join(File.dirname(sectionsplit_fname),
                                     base_filename)
                         else
                           # No directory in pattern
                           base_filename
                         end

        m = { parentid: key, presentationxml: true, type: "fileref",
              rel_path: out_path_value, out_path: out_path_value,
              anchors: anchors, anchors_lookup: anchors_lookup(anchors),
              ids: read_ids(xml), format: @files[key][:format],
              sectionsplit_output: true, indirect_key: @sectionsplit.key,
              bibdata: @files[key][:bibdata], ref: presfile,
              sectionsplit_filename: sectionsplit_fname,
              idx: @files[key][:idx] }
        m[:bare] = true unless idx.zero?
        manifest[newkey] = m
        # Don't delete split output files - we want to keep them!
        # The original parent HTML file is deleted in cleanup_section_split_instance
      end

      def add_section_split_instance_prep(file, key)
        # XML files are always in the root of _files directory
        # Only HTML output files go into subdirectories
        # file[:url] already includes .xml extension
        presfile = File.join(File.dirname(@files[key][:ref]),
                             File.basename(file[:url]))
        newkey = key("#{key.strip} #{file[:title]}")
        xml = Nokogiri::XML(File.read(presfile), &:huge)
        [presfile, newkey, xml]
      end

      def sectionsplit(ident)
        file = @files[ident][:ref]
        # @base must always be just basename, never contain directory components
        # Directory structure comes from sectionsplit_filename pattern only
        base = File.basename(@files[ident][:out_path] || file)
        @sectionsplit = ::Metanorma::Collection::Sectionsplit
          .new(input: file, base: base,
               dir: File.dirname(file), output: @files[ident][:out_path],
               compile_opts: @parent.compile_options, ident: ident,
               fileslookup: self, isodoc: @isodoc,
               parent_idx: @files[ident][:idx],
               sectionsplit_filename: @files[ident][:sectionsplit_filename],
               isodoc_presxml: @isodoc_presxml,
               document_suffix: @files[ident][:document_suffix])
        coll = @sectionsplit.sectionsplit.sort_by { |f| f[:order] }
        xml = Nokogiri::XML(File.read(file, encoding: "UTF-8"), &:huge)
        [coll, @sectionsplit
          .collection_manifest(File.basename(file), coll, xml, nil,
                               File.dirname(file))]
      end
    end
  end
end
