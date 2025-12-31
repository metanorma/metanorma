require_relative "../spec_helper"
require "stringio"

def capture_stdout
  old = $stdout
  $stdout = fake = StringIO.new
  yield
  fake.string
ensure
  $stdout = old
end

INPATH = "spec/fixtures/collection".freeze
OUTPATH = "spec/fixtures/output".freeze

# rubocop:disable Layout/LineLength
RSpec.describe Metanorma::Collection do
  context "render html & build doc, pdf, xml files from" do
    it "YAML collection" do
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.rm_f "#{OUTPATH}/collection1.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml rxl],
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      concat_text = read_and_cleanup "#{INPATH}/collection_full.xml"
      concat_file = read_and_cleanup "#{OUTPATH}/collection.xml"
      expect(Canon.format_xml(cleanup_guid(concat_file.gsub("><", ">\n<")))
        .sub(%r{xlink:href=['"]data:image/gif;base64,[^"']*['"]},
             "xlink:href='data:image/gif;base64,_'"))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(concat_text.gsub("><", ">\n<")))
          .sub(%r{xlink:href=['"]data:image/gif;base64[^"']*['"]},
               "xlink:href='data:image/gif;base64,_'")
      conact_file_doc_xml = Nokogiri::XML(concat_file)
      concat_text_doc_xml = File.open("#{INPATH}/rice-en.final.xml") do |f|
        Nokogiri::XML(f)
      end

      %w[
        Dummy_ISO_17301-1:2016
        StarTrek_ISO_17301-1:2016
        RiceAmd_ISO_17301-1:2016
        _scope_ISO_1701:1974
        _introduction_ISO_17301-1:2016_Amd.1:2017
      ].each do |id|
        warn id
        expect(conact_file_doc_xml.xpath(IsoDoc::Convert.new({})
          .ns("//*[@id='#{id.gsub(':', '_')}']")).length).to_not be_zero
      end
      expect(concat_text_doc_xml.xpath("//xmlns:xref/@target")[-1].text)
        .to be_equivalent_to "_scope"
      expect(conact_file_doc_xml.xpath("//i:xref/@target", "i" => "https://www.metanorma.org/ns/standoc")[-1].text)
        .to be_equivalent_to "_scope_ISO_17301-1_2016"
      expect(concat_text_doc_xml.at("//xmlns:strong/@style").text)
        .to be_equivalent_to "background: url(#svg1); foreground: url(_001); middleground: url(#fig1);"
      expect(conact_file_doc_xml.at("//i:strong/@style", "i" => "https://www.metanorma.org/ns/standoc").text)
        .to be_equivalent_to "background: url(#svg1_ISO_17301-1_2016); foreground: url(_001); middleground: url(#fig1_ISO_17301-1_2016);"

      expect(File.exist?("#{INPATH}/collection1.err.html")).to be true
      expect(File.read("#{INPATH}/collection1.err.html", encoding: "utf-8"))
        .to include "Missing:​express-schema:​E0"
      expect(File.exist?("#{OUTPATH}/collection.rxl")).to be true
      expect(File.read("#{OUTPATH}/collection.rxl", encoding: "utf-8"))
        .to include '<docidentifier type="iso" primary="true">ISO 12345</docidentifier>'
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.pdf")).to be true
      # expect(File.exist?("#{OUTPATH}/collection.doc")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1"
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO&nbsp;17301-1:2016/Amd.1:2017"
      expect(File.exist?("#{OUTPATH}/pics/action_schemaexpg1.svg")).to be true
      expect(File.exist?("#{OUTPATH}/assets/rice_image1.png")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be false
      # expect(File.exist?("#{OUTPATH}/dummy.doc")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.read("#{OUTPATH}/dummy.xml"))
        .not_to be_equivalent_to File.read("#{OUTPATH}/dummy.presentation.xml")
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      rice = File.read("#{OUTPATH}/rice-en.final.html")
      expect(rice).to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      expect(rice).to include %(It is not applicable to cooked rice products, which are not discussed in <a href="#anotherclause_ISO_17301-1_2016"><span class="citesec">Clause 2</span></a> or <a href="#thirdclause_ISO_17301-1_2016"><span class="citesec">Clause 3</span></a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # but that document is not supplied
      expect(rice).to include %{This document uses schemas E0/A0, <a href="example/url.html#A1">E1/A1</a> and <a href="example/url.html#E2">E2</a> as well as <a href="#express-schema_E0_ISO_17301-1_2016">metanorma-collection Missing:express-schema:E0 / current-metanorma-collection/Missing:express-schema:E0</a>.}
      expect(rice).to include %(This document is also unrelated to <a href="example/url.html#what">)
      # resolves erefs to clauses to anchors
      expect(rice).to include %(This document is unrelated <a href="rice1-en.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">1701</span>:<span class="stdyear">1974</span></a>, see e.g. <a href="rice1-en.final.html#scope_ISO_1701_1974"><span class="stdpublisher">ISO </span><span class="stddocNumber">1701</span>:<span class="stdyear">1974</span>,  <span class="citesec">Clause 1</span></a>.)
      FileUtils.rm_rf of
    end

    it "extracts metadata from collection for Liquid" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      cr = Metanorma::Collection::Renderer
        .render(col,
                format: %i[presentation html xml],
                output_folder: of,
                coverpage: "collection_cover.html",
                compile: {
                  install_fonts: false,
                })
      expect(cr.isodoc.meta.get[:bibdata])
        .to eq(
          { "copyright" => [{ "from" => "2020", "owner" => [{ "abbreviation" => { "content" => "ISO" }, "name" => [{ "content" => "International Organization for Standardization" }] }] }],
            "date" => [{ "type" => "created", "value" => "2020" }, { "type" => "issued", "value" => "2020" }],
            "docid" => [{ "id" => "ISO 12345", "type" => "iso", "primary" => "true" }],
            "edition" => { "content" => "1" },
            "id" => "ISO12345",
            "schema-version" => "v1.2.9",
            "title" => [{ "content" => "ISO Collection 1", "format" => "text/plain", "language" => ["en"], "type" => "title-main" }],
            "type" => "collection" },
        )
      expect(cr.isodoc.meta.get[:docrefs])
        .to be_equivalent_to [
          { "identifier" => "ISO 17301-1:2016", "file" => "rice-en.final.html",
            "title" => "Cereals and pulses — Specifications and test methods — Rice (Final)",
            "level" => nil },
          { "identifier" => "ISO 17302:2016", "file" => "dummy.html",
            "title" => "Dummy document", "level" => nil },
          { "identifier" => "ISO 1701:1974", "file" => "rice1-en.final.html",
            "title" => "Test conditions for milling machines with table of " \
                       "variable height, with horizontal or vertical spindle",
            "level" => nil },
          { "identifier" => "ISO 17301-1:2016/Amd.1:2017",
            "file" => "rice-amd.final.html",
            "title" => "Specification and test methods — Rice — Mass fraction of extraneous matter, milled rice (nonglutinous), sample dividers and recommendations relating to storage and transport conditions",
            "level" => nil },
          { "identifier" => "action_schemaexpg1.svg",
            "file" => "pics/action_schemaexpg1.svg", "title" => nil,
            "level" => nil },
          { "identifier" => "rice_image1.png",
            "file" => "assets/rice_image1.png",
            "title" => nil, "level" => nil },
        ]
      expect(cr.isodoc.meta.get[:navigation])
        .to be_equivalent_to <<~OUTPUT
          <ul><li>ISO Collection<ul>
          <li>Standards<ul>
          <li><a href="rice-en.final.html">ISO&nbsp;17301-1:2016</a></li>
          <li><a href="dummy.html">ISO&nbsp;17302:2016</a></li>
          <li><a href="rice1-en.final.html">ISO&nbsp;1701:1974</a></li>
          </ul>
          </li>
          <li>Amendments<ul><li><a href="rice-amd.final.html">ISO&nbsp;17301-1:2016/Amd.1:2017</a></li></ul>
          </li>
          <li>Attachments<ul>
          <li><a href="pics/action_schemaexpg1.svg">action_schemaexpg1.svg</a></li>
          <li><a href="assets/rice_image1.png">rice_image1.png</a></li>
          </ul>
          </li>
          </ul>
          </li></ul>
        OUTPUT
      expect(strip_guid(cr.isodoc.meta.get[:"prefatory-content"]))
        .to be_equivalent_to <<~OUTPUT
          <div>
          <div id="_">
          <h1>Clause</h1>

          <p id="_">Welcome to our collection</p>
          </div>
          </div>
      OUTPUT
      expect(strip_guid(cr.isodoc.meta.get[:"final-content"]))
        .to be_equivalent_to <<~OUTPUT
           <div>
          <div id="_">
          <h1>Exordium</h1>

          <p id="_">Hic explicit</p>
          </div>
          </div>
      OUTPUT
      expect(cr.isodoc.meta.get[:nav_object])
        .to be_equivalent_to (
          { title: "ISO Collection", level: "collection",
            children: [
              { title: "Standards",
                level: "subcollection",
                docrefs: "<ul> <li><a href=\"rice-en.final.html\">ISO&nbsp;17301-1:2016</a></li> <li><a href=\"dummy.html\">ISO&nbsp;17302:2016</a></li> <li><a href=\"rice1-en.final.html\">ISO&nbsp;1701:1974</a></li> </ul>" },
              { title: "Amendments",
                level: "subcollection",
                docrefs: "<ul><li><a href=\"rice-amd.final.html\">ISO 17301-1:2016/Amd.1:2017</a></li></ul>" },
              { title: "Attachments",
                level: "attachments",
                docrefs: "<ul> <li><a href=\"pics/action_schemaexpg1.svg\">action_schemaexpg1.svg</a></li> <li><a href=\"assets/rice_image1.png\">rice_image1.png</a></li> </ul>" },
            ] }
        )
    end

    it "uses presentation XML directive, markup in identifiers, output folder specification in YAML" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection2.yml"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[html presentation xml],
        # output_folder: of,
        coverpage: "collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.read("#{OUTPATH}/dummy.xml"))
        .to be_equivalent_to File.read("#{OUTPATH}/dummy.presentation.xml")
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "1701<sup>x</sup>"
      FileUtils.rm_rf of
    end

    it "invokes PDF portfolios" do
      mock_pdf_portfolio
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.rm_f "#{OUTPATH}/collection1.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = File.join(FileUtils.pwd, OUTPATH)
      formats = %i[presentation pdf xml]
      col = Metanorma::Collection.parse file
      col.render(
        format: formats,
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      expect(pdf_portfolio_used?).to be false
      formats = %i[presentation pdf-portfolio xml]
      col = Metanorma::Collection.parse file
      col.render(
        format: formats,
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      expect(pdf_portfolio_used?).to be true
    end

    it "YAML collection with documents inline" do
      mock_pdf
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf doc xml],
        output_folder: of,
        coverpage: "collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1"
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.doc")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.doc")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml.0.html"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml.1.html"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml.2.html"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.doc")).to be false
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      FileUtils.rm_rf of
    end

    it "YAML collection with nested YAMLs, directory changes, attachments " \
    "with absolute paths, attachments with paths outside working directory, " \
    "implicit identifier for files, svg links outside current file" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.rm_f "#{OUTPATH}/collection1.err.html"
      FileUtils.rm_f "#{INPATH}/document-1/document-1.xml"
      FileUtils.rm_f "#{INPATH}/document-2/document-2.xml"
      file = "#{INPATH}/collection_new.yml"
      # xml = file.read file, encoding: "utf-8"
      of = File.join(FileUtils.pwd, OUTPATH)
      # change file path of attachment in document-2/collection.yml to absolute
      f = "#{INPATH}/document-2/collection.yml"
      a = File.read(f).sub(/img/, "#{File.expand_path(INPATH)}/document-2/img")
      File.open(f, "w") { |x| x.write(a) }
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/document-1.xml.0.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-1.xml.1.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-1.xml.2.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-2.xml.0.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-2.xml.1.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-2.xml.2.html")).to be true
      # from: spec/fixtures/collection/document-1/img/action_schemaexpg2.svg :
      # relative link within working directory spec/fixtures/collection
      expect(File.exist?("#{OUTPATH}/document-1/img/action_schemaexpg2.svg")).to be true
      # from: spec/fixtures/collection/../../../assets/rice_image1.png :
      # relative link outside of working directory spec/fixtures/collection
      expect(File.exist?("#{OUTPATH}/assets/rice_image1.png")).to be true
      # from: //.../spec/fixtures/collection/document-2/img/action_schemaexpg3.svg :
      # absolute link
      expect(File.exist?("#{OUTPATH}/document-2/img/action_schemaexpg3.svg")).to be true
      # resolve link to "../pics/action_schemaexpg1.svg from within document-1/document.adoc
      # to Data URI
      r = File.read("#{OUTPATH}/document-1.xml.1.html")
      expect(r).to include 'xlink:href="data:image/gif'
      expect(r).not_to include "pics/action_schemaexpg1.svg"

      # disambig files
      f = "#{INPATH}/document-2/collection.yml"
      a = File.read(f).sub(%r{fileref: \S+/img/action_schemaexpg3.svg},
                           "fileref: #{File.expand_path(INPATH)}/document-2/img/action_schemaexpg2.svg")
      File.open(f, "w") { |x| x.write(a) }
      FileUtils.rm_f "#{INPATH}/document-1/document-1.xml"
      FileUtils.rm_f "#{INPATH}/document-2/document-2.xml"
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/document-1.xml.0.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-1.xml.1.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-1.xml.2.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-2.xml.0.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-2.xml.1.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-2.xml.2.html")).to be true
      expect(File.exist?("#{OUTPATH}/document-1/img/action_schemaexpg2.svg")).to be true
      expect(File.exist?("#{OUTPATH}/assets/rice_image1.png")).to be true
      # from: //.../spec/fixtures/collection/document-2/img/action_schemaexpg2.svg :
      # ambiguous name
      expect(File.exist?("#{OUTPATH}/document-2/img/action_schemaexpg2.1.svg")).to be true
      FileUtils.rm_f("tmp_document-1.presentation.xml")
      FileUtils.rm_f("tmp_document-2.presentation.xml")
    end

    it "recompiles XML" do
      FileUtils.rm_f "#{INPATH}/document-1/document-1.xml"
      file = "#{INPATH}/document-1/collection.yml"
      a = File.read(file).sub(/- documents-inline/, "- recompile-xml: false\n- documents-inline")
      File.open(file, "w") { |x| x.write(a) }
      Metanorma::Collection.parse file
      expect(File.exist?("#{INPATH}/document-1/document-1.xml")).to be true
      time = File.mtime("#{INPATH}/document-1/document-1.xml")
      Metanorma::Collection.parse file
      expect(File.mtime("#{INPATH}/document-1/document-1.xml")).to be_within(0.1).of time
      a = File.read(file).sub(/- recompile-xml: false/, "- recompile-xml: true")
      File.open(file, "w") { |x| x.write(a) }
      Metanorma::Collection.parse file
      expect(File.mtime("#{INPATH}/document-1/document-1.xml")).not_to be_within(0.1).of time
      a = File.read(file).sub(/- recompile-xml: true/, "- recompile-xml")
      File.open(file, "w") { |x| x.write(a) }
      Metanorma::Collection.parse file
      expect(File.mtime("#{INPATH}/document-1/document-1.xml")).not_to be_within(0.1).of time
      a = File.read(file).sub(/- recompile-xml: true\n/, "\n")
      File.open(file, "w") { |x| x.write(a) }
      Metanorma::Collection.parse file
      expect(File.mtime("#{INPATH}/document-1/document-1.xml")).not_to be_within(0.1).of time
    end
  end

  context "Word collection" do
    it "builds Word collection, no coverpages" do
      file = "#{INPATH}/wordcollection.yml"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation doc pdf],
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      output = File.read("#{OUTPATH}/collection.doc")
      expected = File.read("#{INPATH}/collection.doc")
      # the two images made it into the document
      expect(output).to include "iVBORw0KGgoAAAANSUhEUgAAAaQAAAJnCAYAAADY2CeyAAAAAXNSR0IArs4c6QAAAARnQU1BAACx"
      expect(output).to include "CCQAQAoEEgAgBQIJAJACgQQASIFAAgCkQCABAFIgkAAAKRBIAIAUCCQAQAoEEgAgBQIJAJACgQQA"
      expect(output).to include "mIAkDAAAYAKSMAAAgAlIwgAAACYgCQMAAJiAJAwAAGACkjAAAIAJSMIAAAAmIAkDAACYgCQMAABg"
      expect(output).to include "Content-Type: image/png"
      output.sub!(%r{</html>.*$}m, "</html>").sub!(%r{^.*<html }m, "<html ")
        .sub!(%r{<style>.+</style>}m, "<style/>")
      expect(Canon.format_xml(cleanup_guid(cleanup_id(output))))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(expected))
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.doc")).to be false
      expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be false
      FileUtils.rm_rf of
    end

    it "builds Word collection, coverpage; format overrides in manifest; pdf-file name override" do
      file = "#{INPATH}/wordcollection_cover.yml"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation doc pdf],
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      output = File.read("#{OUTPATH}/collection.doc")
      expected = File.read("#{INPATH}/collection1.doc")
      output.sub!(%r{</html>.*$}m, "</html>").sub!(%r{^.*<html }m, "<html ")
        .sub!(%r{<style>.+</style>}m, "<style/>")
      expect(Canon.format_xml(cleanup_guid(cleanup_id(output))))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(expected))
      expect(File.exist?("#{OUTPATH}/dummy.doc")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be false
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be false
      expect(File.exist?("#{OUTPATH}/riceamd.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be false
      FileUtils.rm_rf of
    end
  end

  context "bilingual document" do
    it "YAML collection" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.rm_f "#{OUTPATH}/collection1.err.html"
      file = "#{INPATH}/bilingual.yml"
      of = File.join(FileUtils.pwd, OUTPATH)
      col = Metanorma::Collection.parse file
      col.render(
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      concat_text = cleanup_guid(read_and_cleanup("#{INPATH}/bilingual.presentation.xml"))
      concat_file = cleanup_guid(read_and_cleanup("#{OUTPATH}/collection.presentation.xml"))
      x = Nokogiri::XML(concat_file).at(".//xmlns:doc-container")
      # remember to strip these from bilingual.presentation.xml when saving new version of file
      x.at(".//*[local-name() = 'metanorma-extension']")&.remove
      x.at(".//*[local-name() = 'localized-strings']")&.remove
      a = Canon.format_xml(cleanup_guid(x.to_xml))
        .sub(%r{xlink:href=['"]data:image/gif;base64,[^"']*['"]},
             "xlink:href='data:image/gif;base64,_'")
        .gsub(%r{<localized-strings>.*?</localized-strings>}m, "<localized-strings/>")
      b = Canon.format_xml(concat_text)
        .sub(%r{xlink:href=['"]data:image/gif;base64[^"']*['"]},
             "xlink:href='data:image/gif;base64,_'")
      expect(a).to be_analogous_with b
    end
  end
end
