require "yaml"
require "fileutils"
require_relative "../../util/util"
require_relative "../xrefprocess/xrefprocess"
require_relative "collection"
require "concurrent-ruby"

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
        @isodoc_presxml = opts[:isodoc_presxml]
        @document_suffix = opts[:document_suffix]
        @sectionsplit_filename = opts[:sectionsplit_filename] ||
          "{basename_legacy}.{sectionsplit-num}"
        @parent_idx = opts[:parent_idx] || 0
      end

      def ns(xpath)
        @isodoc.ns(xpath)
      end

      SPLITSECTIONS =
        [["//preface/*", "preface"], ["//sections/*", "sections"],
         ["//annex", nil],
         ["//bibliography/*[not(@hidden = 'true')]", "bibliography"],
         ["//indexsect", nil], ["//colophon", nil]].freeze

      # Input XML is Semantic XML
      def sectionsplit
        xml = sectionsplit_prep(File.read(@input_filename), @base, @dir)
        @key = Metanorma::Collection::XrefProcess::xref_preprocess(xml, @isodoc)
        empty = empty_doc(xml)
        empty1 = empty_attachments(empty)
        @mutex = Mutex.new
        # @pool = Concurrent::FixedThreadPool.new(4)
        @pool = Concurrent::FixedThreadPool.new(1)
        sectionsplit1(xml, empty, empty1, 0)
      end

      # xml is Presentation XML
      def sectionsplit1(xml, empty, empty1, idx)
        ret = SPLITSECTIONS.each_with_object([]) do |n, m|
          conflate_floatingtitles(xml.xpath(ns(n[0]))).each do |s|
            # require "debug"; binding.b
            sectionsplit2(xml, idx.zero? ? empty : empty1, s, n[1],
                          { acc: m, idx: idx })
            idx += 1
          end
        end
        @pool.shutdown
        @pool.wait_for_termination
        ret
      end

      def sectionsplit2(xml, empty, chunks, parentnode, opt)
        @pool.post do
          output_filename = @sectionsplit_filename
            &.gsub(/\{document-num\}/, @parent_idx.to_s)
            &.gsub(/\{basename_legacy\}/, @base)
            &.gsub(/\{basename\}/, File.basename(@base, ".*"))
            &.gsub(/\{sectionsplit-num\}/, opt[:idx].to_s)
          warn "Sectionsplit: #{output_filename}"
          a = sectionfile(xml, empty, output_filename, chunks,
                          parentnode)
          @mutex.synchronize { opt[:acc] << a }
        end
      end

      # TODO move to metanorma-utils
      def block?(node)
        %w(p table formula admonition ol ul dl figure quote sourcecode example
           pre note pagebreak hr bookmark requirement recommendation permission
           svgmap inputform toc passthrough annotation imagemap).include?(node.name)
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
        xml, type = sectionsplit_preprocess_semxml(file, filename)
        flags = { format: :asciidoc, extension_keys: [:presentation],
                  type: type }.merge(@compile_opts)
        Compile.new.compile(xml, flags)
        f = File.open(xml.sub(/\.xml$/, ".presentation.xml"), encoding: "utf-8")
        r = Nokogiri::XML(f, &:huge)
        f.close
        r.xpath("//xmlns:svgmap1").each { |x| x.name = "svgmap" }
        r
      end

      def sectionsplit_preprocess_semxml(file, filename)
        xml = Nokogiri::XML(file, &:huge)
        type = xml.root["flavor"]
        type ||= xml.root.name.sub("-standard", "").to_sym
        sectionsplit_update_xrefs(xml)
        xml1 = sectionsplit_write_semxml(filename, xml)
        @tmp_filename = xml1
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
        outname = Pathname.new("tmp_#{filename}").sub_ext(".xml").to_s
        File.open(outname, "w:UTF-8") do |f|
          f.write(@isodoc.to_xml(xml))
        end
        outname
      end

      def empty_doc(xml)
        out = xml.dup
        out.xpath(
          ns("//preface | //sections | //annex | " \
          "//references/bibitem[not(@hidden = 'true')] | " \
          "//indexsect | //colophon"),
        ).each(&:remove)
        ::Metanorma::Collection::Util::hide_refs(out)
        out
      end

      def empty_attachments(xml)
        xml.dup
      end

      def sectionfile(fulldoc, xml, file, chunks, parentnode)
        fname = create_sectionfile(fulldoc, xml.dup, file, chunks, parentnode)
        { order: chunks.last["displayorder"].to_i, url: fname,
          title: titlerender(chunks.last) }
      end

      def create_sectionfile(xml, out, file, chunks, parentnode)
        ins = out.at(ns("//metanorma-extension")) || out.at(ns("//bibdata"))
        sectionfile_insert(ins, chunks, parentnode)
        sectionfile_fn_filter(sectionfile_annotation_filter(out))
        Metanorma::Collection::XrefProcess::xref_process(out, xml, @key,
                                                         @ident, @isodoc, true)
        # XML files always go in root of splitdir, only HTML files use subdirectories
        xml_filename = "#{File.basename(file)}.xml"
        full_path = File.join(@splitdir, xml_filename)
        File.open(full_path, "w:UTF-8") { |f| f.write(out) }
        # Return filename with .xml extension (for reading later) and directory (for HTML output)
        # file parameter already contains directory if sectionsplit_filename has one
        "#{file}.xml"
      end

      def sectionfile_insert(ins, chunks, parentnode)
        if parentnode
          ins.next = "<#{parentnode}/>"
          chunks.each { |c| ins.next.add_child(c.dup) }
        else chunks.each { |c| ins.next = c.dup }
        end
      end

      def sectionfile_fn_filter(xml)
        ids = sectionfile_fn_filter_prep(xml)
        xml.root.xpath(ns("./fmt-footnote-container/fmt-fn-body")).each do |f|
          ids.has_key?(f["id"]) or f.remove
        end
        seen = {}
        xml.root.xpath(ns("/fmt-footnote-container/fmt-fn-body"))
          .each_with_index do |fnbody, i|
            sectionfile_fn_filter_renumber(fnbody, i, ids, seen)
          end
        xml
      end

      # map fmt-fn-body/@id = fn/@target to fn
      def sectionfile_fn_filter_prep(xml)
        xml.xpath(ns("//fn")).each_with_object({}) do |f, m|
          m[f["target"]] ||= []
          m[f["target"]] << f
        end
      end

      FN_CAPTIONS = ".//fmt-fn-label/span[@class = 'fmt-caption-label']".freeze

      def sectionfile_fn_filter_renumber(fnbody, idx, ids, seen)
        sectionfile_fn_filter_fn_renumber(fnbody, idx, ids, seen)
        sectionfile_fn_filter_fnbody_renumber(fnbody, idx, ids)
      end

      def sectionfile_fn_filter_fn_renumber(fnbody, idx, ids, seen)
        ids[fnbody["id"]].each do |f|
          @isodoc_presxml.renumber_document_footnote(f, idx, seen)
          fnlabel = f.at(ns(FN_CAPTIONS)) and
            fnlabel.children = @isodoc_presxml.fn_ref_label(f)
        end
      end

      def sectionfile_fn_filter_fnbody_renumber(fnbody, _idx, ids)
        fnlabel = fnbody.at(ns(FN_CAPTIONS)) or return
        fnbody["reference"] = ids[fnbody["id"]].first["reference"]
        fnlabel.children = @isodoc_presxml.fn_body_label(fnbody)
      end

      # map fmt-annotation-body/@id = fmt-annotation-{start/end}/@target
      # to fmt-annotation-{start/end}
      def sectionfile_annotation_filter_prep(xml)
        xml.xpath(ns("//fmt-annotation-start | //fmt-annotation-end"))
          .each_with_object({}) do |f, m|
            m[f["target"]] ||= []
            m[f["target"]] << f
          end
      end

      def sectionfile_annotation_filter(xml)
        ids = sectionfile_annotation_filter_prep(xml)
        xml.root.xpath(ns("./annotation-container/fmt-annotation-body"))
          .each do |f|
          ids.has_key?(f["id"]) or f.remove
        end
        xml.root.xpath(ns("./annotation-container/fmt-annotation-body"))
          .each_with_index do |fnbody, i|
            sectionfile_annotation_filter_renumber(fnbody, i, ids)
          end
        xml
      end

      def sectionfile_annotation_filter_renumber(fnbody, _idx, ids)
        ids[fnbody["id"]].each do |f|
          case f.name
          when "fmt-annotation-start"
            f.children = @isodoc_presxml.comment_bookmark_start_label(f)
          when "fmt-annotation-end"
            f.children = @isodoc_presxml.comment_bookmark_end_label(f)
          end
        end
      end

      def titlerender(section)
        title = section.at(ns("./fmt-title")) or return "[Untitled]"
        t = title.dup
        t.xpath(ns(".//tab | .//br")).each { |x| x.replace(" ") }
        t.xpath(ns(".//bookmark")).each(&:remove)
        t.xpath(".//text()").map(&:text).join
      end
    end
  end
end
