module Metanorma
  class Collection
    class Sectionsplit
      def build_collection
        collection_setup(@base, @dir)
        files = sectionsplit
        input_xml = Nokogiri::XML(File.read(@input_filename,
                                            encoding: "UTF-8"), &:huge)
        collection_manifest(@base, files, input_xml, @xml, @dir).render(
          { format: %i(html), output_folder: "#{@output_filename}_collection",
            coverpage: File.join(@dir, "cover.html") }.merge(@compile_opts),
        )
        section_split_attachments(out: "#{@output_filename}_collection")
      end

      def collection_setup(filename, dir)
        FileUtils.mkdir_p "#{filename}_collection" if filename
        FileUtils.mkdir_p dir
        File.open(File.join(dir, "cover.html"), "w:UTF-8") do |f|
          f.write(coll_cover)
        end
      end

      def coll_cover
        <<~COVER
          <html><head><meta charset="UTF-8"/></head><body>
                <h1>{{ doctitle }}</h1>
                <h2>{{ docnumber }}</h2>
                <nav>{{ navigation }}</nav>
              </body></html>
        COVER
      end

      def collection_manifest(filename, files, origxml, _presxml, dir)
        File.open(File.join(dir, "#{filename}.html.yaml"), "w:UTF-8") do |f|
          f.write(collectionyaml(files, origxml))
        end
        Metanorma::Collection.parse File.join(dir, "#{filename}.html.yaml")
      end

      def collectionyaml(files, xml)
        ret = {
          directives: ["presentation-xml", "bare-after-first"],
          bibdata: {
            title: {
              type: "title-main", language: @lang,
              content: xml.at(ns("//bibdata/title")).text
            },
            type: "collection",
            docid: {
              type: xml.at(ns("//bibdata/docidentifier/@type")).text,
              id: xml.at(ns("//bibdata/docidentifier")).text,
            },
          },
          manifest: {
            level: "collection", title: "Collection",
            docref: files.sort_by { |f| f[:order] }.each.map do |f|
              { fileref: f[:url], identifier: f[:title] }
            end
          },
        }
        ::Metanorma::Util::recursive_string_keys(ret).to_yaml
      end

      def att_dir(file)
        "_#{File.basename(file, '.*')}_attachments"
      end

      def section_split_attachments(out: nil)
        attachments = att_dir(@tmp_filename)
        File.directory?(attachments) or return
        dir = out || File.dirname(@input_filename)
        ret = File.join(dir, att_dir(@output_filename))
        FileUtils.rm_rf ret
        FileUtils.mv attachments, ret
        File.basename(ret)
      end

      def section_split_cover(col, ident, _one_doc_coll)
        dir = File.dirname(col.file)
        collection_setup(nil, dir)
        r = ::Metanorma::Collection::Renderer
          .new(col, dir, output_folder: "#{ident}_collection",
                         format: %i(html), coverpage: File.join(dir, "cover.html"))
        r.coverpage
        section_split_cover1(ident, r, dir, _one_doc_coll)
      end

      def section_split_cover1(ident, renderer, dir, _one_doc_coll)
        # filename = one_doc_coll ? "#{ident}_index.html" : "index.html"
        filename = File.basename("#{ident}_index.html")
        # ident can be a directory with YAML indirection
        FileUtils.mv File.join(renderer.outdir, "index.html"),
                     File.join(dir, filename)
        FileUtils.rm_rf renderer.outdir
        filename
      end
    end
  end
end
