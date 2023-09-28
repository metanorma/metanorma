module Metanorma
  # XML collection renderer
  class FileLookup
    def add_section_split
      ret = @files.keys.each_with_object({}) do |k, m|
        if @files[k][:sectionsplit] == "true" && !@files[k]["attachment"]
          s, manifest = sectionsplit(@files[k][:ref], k)
          s.each_with_index { |f1, i| add_section_split_instance(f1, m, k, i) }
          m["#{k}:index.html"] = add_section_split_cover(manifest, k)
          @files_to_delete << m["#{k}:index.html"][:ref]
        end
        m[k] = @files[k]
      end
      @files = ret
    end

    def add_section_split_cover(manifest, ident)
      cover = @sectionsplit
        .section_split_cover(manifest, @parent.dir_name_cleanse(ident),
                             one_doc_collection?)
      @files[ident][:out_path] = cover
      { attachment: true, index: false, out_path: cover,
        ref: File.join(File.dirname(manifest.file), cover) }
    end

    def one_doc_collection?
      docs = 0
      @files.each_value do |v|
        v[:attachment] and next
        v[:presentationxml] and next
        docs += 1
      end
      docs > 1
    end

    def add_section_split_instance(file, manifest, key, idx)
      presfile, newkey, xml =
        add_section_split_instance_prep(file, key)
      manifest[newkey] =
        { parentid: key, presentationxml: true, type: "fileref",
          rel_path: file[:url], out_path: File.basename(file[:url]),
          anchors: read_anchors(xml), ids: read_ids(xml),
          sectionsplit_output: true,
          bibdata: @files[key][:bibdata], ref: presfile }
      @files_to_delete << file[:url]
      manifest[newkey][:bare] = true unless idx.zero?
    end

    def add_section_split_instance_prep(file, key)
      presfile = File.join(File.dirname(@files[key][:ref]),
                           File.basename(file[:url]))
      newkey = key("#{key.strip} #{file[:title]}")
      xml = Nokogiri::XML(File.read(presfile), &:huge)
      [presfile, newkey, xml]
    end

    def sectionsplit(file, ident)
      @sectionsplit = Sectionsplit
        .new(input: file, base: File.basename(file), dir: File.dirname(file),
             output: file, compile_options: @parent.compile_options,
             fileslookup: self, ident: ident, isodoc: @isodoc)
      coll = @sectionsplit.sectionsplit.sort_by { |f| f[:order] }
      xml = Nokogiri::XML(File.read(file, encoding: "UTF-8"), &:huge)
      [coll, @sectionsplit
        .collection_manifest(File.basename(file), coll, xml, nil,
                             File.dirname(file))]
    end
  end
end
