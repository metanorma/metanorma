require "yaml"
require_relative "../../util/util"
require_relative "../xrefprocess/xrefprocess"

module Metanorma
  class Collection
    class Sectionsplit
      attr_accessor :filecache, :key

      def initialize(opts)
        @input_filename = opts[:input]
        @base = opts[:base]
        @output_filename = opts[:output]
        @xml = opts[:xml]
        @dir = opts[:dir]
        @compile_opts = opts[:compile_opts] || {}
        @fileslookup = opts[:fileslookup]
        @ident = opts[:ident]
        @isodoc = opts[:isodoc]
      end

      def ns(xpath)
        @isodoc.ns(xpath)
      end

      def build_collection
        collection_setup(@base, @dir)
        files = sectionsplit # (@input_filename, @base, @dir, @compile_opts)
        input_xml = Nokogiri::XML(File.read(@input_filename,
                                            encoding: "UTF-8"), &:huge)
        collection_manifest(@base, files, input_xml, @xml, @dir).render(
          { format: %i(html), output_folder: "#{@output_filename}_collection",
            coverpage: File.join(@dir, "cover.html") }.merge(@compile_opts),
        )
      end

      def collection_manifest(filename, files, origxml, _presxml, dir)
        File.open(File.join(dir, "#{filename}.html.yaml"), "w:UTF-8") do |f|
          f.write(collectionyaml(files, origxml))
        end
        Metanorma::Collection.parse File.join(dir, "#{filename}.html.yaml")
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

      SPLITSECTIONS =
        [["//preface/*", "preface"], ["//sections/*", "sections"],
         ["//annex", nil],
         ["//bibliography/*[not(@hidden = 'true')]", "bibliography"],
         ["//indexsect", nil], ["//colophon", nil]].freeze

      # Input XML is Semantic
      # def sectionsplit(filename, basename, dir, compile_options, fileslookup = nil, ident = nil)
      def sectionsplit
        xml = sectionsplit_prep(File.read(@input_filename), @base, @dir)
        @key = Metanorma::Collection::XrefProcess::xref_preprocess(xml, @isodoc)
        SPLITSECTIONS.each_with_object([]) do |n, ret|
          conflate_floatingtitles(xml.xpath(ns(n[0]))).each do |s|
            ret << sectionfile(xml, emptydoc(xml), "#{@base}.#{ret.size}", s,
                               n[1])
          end
        end
      end

      def block?(node)
        %w(p table formula admonition ol ul dl figure quote sourcecode example
           pre note pagebrreak hr bookmark requirement recommendation permission
           svgmap inputform toc passthrough review imagemap).include?(node.name)
      end

      def conflate_floatingtitles(nodes)
        holdover = false
        nodes.each_with_object([]) do |x, m|
          if holdover then m.last << x
          else m << [x]
          end
          holdover = block?(x)
        end
      end

      def sectionsplit_prep(file, filename, dir)
        @splitdir = dir
        xml1, type = sectionsplit_preprocess_semxml(file, filename)
        flags = { format: :asciidoc, extension_keys: [:presentation],
                  type: type }.merge(@compile_opts)
        Compile.new.compile(xml1, flags)
        f = File.open(xml1.sub(/\.xml$/, ".presentation.xml"),
                      encoding: "utf-8")
        r = Nokogiri::XML(f, &:huge)
        r.xpath("//xmlns:svgmap1").each { |x| x.name = "svgmap" }
        r
      end

      def sectionsplit_preprocess_semxml(file, filename)
        xml = Nokogiri::XML(file, &:huge)
        type = xml.root.name.sub("-standard", "").to_sym
        sectionsplit_update_xrefs(xml)
        xml1 = sectionsplit_write_semxml(filename, xml)
        # @filecache ||= []
        # @filecache << xml1
        # [xml1.path, type]
        [xml1, type]
      end

      def sectionsplit_update_xrefs(xml)
        if c = @fileslookup&.parent
          n = c.nested
          c.nested = true # so unresolved erefs are not deleted
          c.update_xrefs(xml, @ident, {})
          c.nested = n
          xml.xpath("//xmlns:svgmap").each { |x| x.name = "svgmap1" }
          # do not process svgmap until after files are split
        end
      end

      def sectionsplit_write_semxml(filename, xml)
        #         Tempfile.open([filename, ".xml"], encoding: "utf-8") do |f|
        #           f.write(@isodoc.to_xml(xml))
        #           f
        #         end
        outname = Pathname.new("tmp_#{filename}").sub_ext(".xml").to_s
        File.open(outname, "w:UTF-8") do |f|
          f.write(@isodoc.to_xml(xml))
        end
        outname
      end

      def emptydoc(xml)
        out = xml.dup
        out.xpath(
          ns("//preface | //sections | //annex | //bibliography/clause | " \
             "//bibliography/references[not(@hidden = 'true')] | //indexsect | " \
             "//colophon"),
        ).each(&:remove)
        out
      end

      def sectionfile(fulldoc, xml, file, chunks, parentnode)
        fname = create_sectionfile(fulldoc, xml.dup, file, chunks, parentnode)
        { order: chunks.last["displayorder"].to_i, url: fname,
          title: titlerender(chunks.last) }
      end

      def create_sectionfile(xml, out, file, chunks, parentnode)
        ins = out.at(ns("//metanorma-extension")) || out.at(ns("//bibdata"))
        sectionfile_insert(ins, chunks, parentnode)
        Metanorma::Collection::XrefProcess::xref_process(out, xml, @key,
                                                         @ident, @isodoc)
        outname = "#{file}.xml"
        File.open(File.join(@splitdir, outname), "w:UTF-8") do |f|
          f.write(out)
        end
        outname
      end

      def sectionfile_insert(ins, chunks, parentnode)
        if parentnode
          ins.next = "<#{parentnode}/>"
          chunks.each { |c| ins.next.add_child(c.dup) }
        else chunks.each { |c| ins.next = c.dup }
        end
      end

      def titlerender(section)
        title = section.at(ns("./title")) or return "[Untitled]"
        t = title.dup
        t.xpath(ns(".//tab | .//br")).each { |x| x.replace(" ") }
        t.xpath(ns(".//strong")).each { |x| x.replace(x.children) }
        t.children.to_xml
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

      def section_split_cover(col, ident, _one_doc_coll)
        dir = File.dirname(col.file)
        collection_setup(nil, dir)
        r = ::Metanorma::Collection::Renderer
          .new(col, dir, output_folder: "#{ident}_collection",
                         format: %i(html), coverpage: File.join(dir, "cover.html"))
        r.coverpage
        # filename = one_doc_coll ? "#{ident}_index.html" : "index.html"
        filename = File.basename("#{ident}_index.html") # ident can be a directory with YAML indirection
        FileUtils.mv File.join(r.outdir, "index.html"), File.join(dir, filename)
        FileUtils.rm_rf r.outdir
        filename
      end
    end
  end
end
