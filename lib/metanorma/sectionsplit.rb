require "yaml"
require_relative "util"
require_relative "sectionsplit_links"

module Metanorma
  class Compile
    # assume we pass in Presentation XML, but we want to recover Semantic XML
    def sectionsplit_convert(input_filename, file, output_filename = nil,
                             opts = {})
      @isodoc = IsoDoc::Convert.new({})
      input_filename += ".xml" unless input_filename.match?(/\.xml$/)
      File.exist?(input_filename) or
        File.open(input_filename, "w:UTF-8") { |f| f.write(file) }
      presxml = File.read(input_filename, encoding: "utf-8")
      @openmathdelim, @closemathdelim = @isodoc.extract_delims(presxml)
      _xml, filename, dir = @isodoc.convert_init(presxml, input_filename, false)
      build_collection(input_filename, presxml,
                       output_filename || filename, dir, opts)
    end

    def ns(xpath)
      @isodoc.ns(xpath)
    end

    def build_collection(input_filename, presxml, filename, dir, opts = {})
      base = File.basename(filename)
      collection_setup(base, dir)
      files = sectionsplit(input_filename, base, dir, opts)
      xml = Nokogiri::XML(File.read(input_filename, encoding: "UTF-8"))
      collection_manifest(base, files, xml, presxml, dir).render(
        { format: %i(html), output_folder: "#{filename}_collection",
          coverpage: File.join(dir, "cover.html") }.merge(opts),
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
        <html><head/><body>
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
    def sectionsplit(filename, basename, dir, compile_options)
      xml = sectionsplit_prep(File.read(filename), basename, compile_options)
      @key = xref_preprocess(xml)
      @splitdir = dir
      out = emptydoc(xml)
      SPLITSECTIONS.each_with_object([]) do |n, ret|
        xml.xpath(ns(n[0])).each do |s|
          ret << sectionfile(xml, out, "#{basename}.#{ret.size}", s, n[1])
        end
      end
    end

    def sectionsplit_prep(file, filename, compile_options)
      xml1filename, type = sectionsplit_preprocess_semxml(file, filename)
      compile(
        xml1filename,
        { format: :asciidoc, extension_keys: [:presentation], type: type }
       .merge(compile_options),
      )
      Nokogiri::XML(File.read(xml1filename.sub(/\.xml$/, ".presentation.xml"),
                              encoding: "utf-8"))
    end

    def sectionsplit_preprocess_semxml(file, filename)
      xml = Nokogiri::XML(file)
      type = xml.root.name.sub("-standard", "").to_sym
      xml1 = Tempfile.open([filename, ".xml"], encoding: "utf-8") do |f|
        f.write(@isodoc.to_xml(svg_preprocess(xml)))
        f
      end
      @filecache ||= []
      @filecache << xml1
      [xml1.path, type]
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

    def sectionfile(fulldoc, xml, file, chunk, parentnode)
      fname = create_sectionfile(fulldoc, xml.dup, file, chunk, parentnode)
      { order: chunk["displayorder"].to_i, url: fname,
        title: titlerender(chunk) }
    end

    def create_sectionfile(xml, out, file, chunk, parentnode)
      ins = out.at(ns("//metanorma-extension")) || out.at(ns("//bibdata"))
      if parentnode
        ins.next = "<#{parentnode}/>"
        ins.next.add_child(chunk.dup)
      else ins.next = chunk.dup
      end
      xref_process(out, xml, @key)
      outname = "#{file}.xml"
      File.open(File.join(@splitdir, outname), "w:UTF-8") { |f| f.write(out) }
      outname
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
      Util::recursive_string_keys(ret).to_yaml
    end
  end
end
