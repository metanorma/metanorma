require_relative "../sectionsplit/sectionsplit"
# require "concurrent-ruby"

module Metanorma
  class Collection
    class FileLookup
      def add_section_split
        ret = @files.keys.each_with_object({}) do |k, m|
          if @files[k][:sectionsplit] && !@files[k][:attachment]
            process_section_split_instance(k, m)
            cleanup_section_split_instance(k, m)
          end
          m[k] = @files[k]
        end
        @files = ret
      end

      def process_section_split_instance(key, manifest)
        s, sectionsplit_manifest = sectionsplit(key)
        # section_split_instance_threads(s, manifest, key)
        s.each_with_index do |f1, i|
          add_section_split_instance(f1, manifest, key, i)
        end
        a = add_section_split_attachments(sectionsplit_manifest, key) and
          manifest["#{key}:attachments"] = a
        add_section_split_cover(manifest, sectionsplit_manifest, key)
      end

      def section_split_instance_threads(s, manifest, key)
        @mutex = Mutex.new
        pool = Concurrent::FixedThreadPool.new(6)
        s.each_with_index do |f1, i|
          pool.post do
            add_section_split_instance(f1, manifest, key, i)
          end
        end
        pool.shutdown
        pool.wait_for_termination
      end

      def cleanup_section_split_instance(key, manifest)
        @files_to_delete << manifest["#{key}:index.html"][:ref]
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
        m = { parentid: key, presentationxml: true, type: "fileref",
              rel_path: file[:url], out_path: File.basename(file[:url]),
              anchors: anchors, anchors_lookup: anchors_lookup(anchors),
              ids: read_ids(xml),
              sectionsplit_output: true, indirect_key: @sectionsplit.key,
              bibdata: @files[key][:bibdata], ref: presfile }
        m[:bare] = true unless idx.zero?
        manifest[newkey] = m
        @files_to_delete << file[:url]
      end

      def add_section_split_instance_prep(file, key)
        presfile = File.join(File.dirname(@files[key][:ref]),
                             File.basename(file[:url]))
        newkey = key("#{key.strip} #{file[:title]}")
        xml = Nokogiri::XML(File.read(presfile), &:huge)
        [presfile, newkey, xml]
      end

      def sectionsplit(ident)
        file = @files[ident][:ref]
        @sectionsplit = ::Metanorma::Collection::Sectionsplit
          .new(input: file, base: @files[ident][:out_path],
               dir: File.dirname(file), output: @files[ident][:out_path],
               compile_opts: @parent.compile_options,
               fileslookup: self, ident: ident, isodoc: @isodoc,
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
