require "yaml"
require_relative "../../util/util"
require_relative "../xrefprocess/xrefprocess"
require_relative "collection"

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

      SPLITSECTIONS =
        [["//preface/*", "preface"], ["//sections/*", "sections"],
         ["//annex", nil],
         ["//bibliography/*[not(@hidden = 'true')]", "bibliography"],
         ["//indexsect", nil], ["//colophon", nil]].freeze

      # Input XML is Semantic
      def sectionsplit
        xml = sectionsplit_prep(File.read(@input_filename), @base, @dir)
        @key = Metanorma::Collection::XrefProcess::xref_preprocess(xml, @isodoc)
        SPLITSECTIONS.each_with_object([]) do |n, ret|
          conflate_floatingtitles(xml.xpath(ns(n[0]))).each do |s|
            ret << sectionfile(xml, emptydoc(xml, ret.size),
                               "#{@base}.#{ret.size}", s, n[1])
          end
        end
      end

      def block?(node)
        %w(p table formula admonition ol ul dl figure quote sourcecode example
           pre note pagebreak hr bookmark requirement recommendation permission
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

      def emptydoc(xml, ordinal)
        out = xml.dup
        out.xpath(
          ns("//preface | //sections | //annex | //bibliography/clause | " \
             "//bibliography/references[not(@hidden = 'true')] | " \
             "//indexsect | //colophon"),
        ).each(&:remove)
        ordinal.zero? or out.xpath(ns("//metanorma-ext//attachment || " \
                      "//semantic__metanorma-ext//semantic__attachment"))
          .each(&:remove) # keep only one copy of attachments
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
        truncate_semxml(out, chunks)
        outname = "#{file}.xml"
        File.open(File.join(@splitdir, outname), "w:UTF-8") { |f| f.write(out) }
        outname
      end

      def semantic_xml_ids_gather(out)
        out.at(ns("//semantic__bibdata")) or return
        SPLITSECTIONS.each_with_object({}) do |s, m|
          out.xpath(ns(s[0].sub("//", "//semantic__"))).each do |x|
            x["id"] or next
            m[x["id"].sub(/^semantic__/, "")] = x
          end
        end
      end

      def semxml_presxml_nodes_match(nodes, chunks)
        chunks.each do |x|
          nodes[x["id"]] and nodes.delete(x["id"])
        end
      end

      def truncate_semxml(out, chunks)
        # require  "debug"; binding.b
        nodes = semantic_xml_ids_gather(out) or return
        semxml_presxml_nodes_match(nodes, chunks)
        nodes.each_value(&:remove)
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
        t.xpath(ns(".//bookmark")).each(&:remove)
        t.xpath(ns(".//strong | .//span"))
          .each { |x| x.replace(x.children) }
        t.children.to_xml
      end
    end
  end
end
