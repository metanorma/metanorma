# frozen_string_literal: true

require "stringio"

def capture_stdout
  old = $stdout
  $stdout = fake = StringIO.new
  yield
  fake.string
ensure
  $stdout = old
end

INPATH = "spec/fixtures/collection"
OUTPATH = "spec/fixtures/ouput"
GUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

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
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml],
        output_folder: of,
        # coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      concat_text = read_and_cleanup "#{INPATH}/collection_full.xml"
      concat_file = read_and_cleanup "#{OUTPATH}/collection.xml"
      expect(Xml::C14n.format(cleanup_guid(concat_file.gsub("><", ">\n<")))
        .sub(%r{xlink:href=['"]data:image/gif;base64,[^"']*['"]},
             "xlink:href='data:image/gif;base64,_'"))
        .to be_equivalent_to Xml::C14n.format(cleanup_guid(concat_text.gsub("><", ">\n<")))
          .sub(%r{xlink:href=['"]data:image/gif;base64[^"']*['"]},
               "xlink:href='data:image/gif;base64,_'")
      conact_file_doc_xml = Nokogiri::XML(concat_file)
      concat_text_doc_xml = File.open("#{INPATH}/rice-en.final.xml") do |f|
        Nokogiri::XML(f)
      end

      %w[
        Dummy_ISO_17301-1_2016
        StarTrek_ISO_17301-1_2016
        RiceAmd_ISO_17301-1_2016
        _scope_ISO_1701_1974
        _introduction_ISO_17301-1_2016_Amd.1_2017
      ].each do |id|
        expect(conact_file_doc_xml.xpath(IsoDoc::Convert.new({})
          .ns("//*[@id='#{id}']")).length).to_not be_zero
      end
      expect(concat_text_doc_xml.xpath("//xmlns:xref/@target")[-1].text)
        .to be_equivalent_to "_scope"
      expect(conact_file_doc_xml.xpath("//i:xref/@target", "i" => "https://www.metanorma.org/ns/iso")[-1].text)
        .to be_equivalent_to "_scope_ISO_17301-1_2016"
      expect(concat_text_doc_xml.at("//xmlns:strong/@style").text)
        .to be_equivalent_to "background: url(#svg1); foreground: url(_001); middleground: url(#fig1);"
      expect(conact_file_doc_xml.at("//i:strong/@style", "i" => "https://www.metanorma.org/ns/iso").text)
        .to be_equivalent_to "background: url(#svg1_ISO_17301-1_2016); foreground: url(_001); middleground: url(#fig1_ISO_17301-1_2016);"

      expect(File.exist?("#{INPATH}/collection1.err.html")).to be true
      expect(File.read("#{INPATH}/collection1.err.html", encoding: "utf-8"))
        .to include "Missing:​express-schema:​E0"
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1"
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO&nbsp;17301-1:2016/Amd.1:2017"
      expect(File.exist?("#{OUTPATH}/pics/action_schemaexpg1.svg")).to be true
      expect(File.exist?("#{OUTPATH}/assets/rice_image1.png")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.read("#{OUTPATH}/dummy.xml"))
        .not_to be_equivalent_to File.read("#{OUTPATH}/dummy.presentation.xml")
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be true
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
      expect(rice).to include %{This document uses schemas E0/A0, <a href="example/url.html#A1">E1/A1</a> and <a href="example/url.html#E2">E2</a>.}
      expect(rice).to include %(This document is also unrelated to <a href="example/url.html#what">)
      FileUtils.rm_rf of
    end

    it "extracts metadata from collection for Liquid" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      cr = Metanorma::Collection::Renderer
        .render(col,
                format: %i[presentation html xml],
                output_folder: of,
                coverpage: "#{INPATH}/collection_cover.html",
                compile: {
                  install_fonts: false,
                })
      expect(cr.isodoc.meta.get[:bibdata])
        .to eq(
          { "copyright" => [{ "from" => "2020", "owner" => [{ "abbreviation" => { "content" => "ISO" }, "name" => [{ "content" => "International Organization for Standardization" }] }] }],
            "date" => [{ "type" => "created", "value" => "2020" }, { "type" => "issued", "value" => "2020" }],
            "docid" => [{ "id" => "ISO 12345", "type" => "iso" }],
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

    it "uses presentation XML directive, markup in identifiers" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection2.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[html presentation xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
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

    it "YAML collection with documents inline" do
      mock_pdf
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
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
      # expect(File.exist?("#{OUTPATH}/dummy.doc")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be true
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
      # expect(File.exist?("#{OUTPATH}/rice1-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      FileUtils.rm_rf of
    end

    it "processes section split HTML" do
      FileUtils.rm_rf "test_collection"
      FileUtils.rm_rf "test_files"
      mock_render
      Metanorma::Compile.new.compile("spec/fixtures/test_sectionsplit.xml",
                                     type: "iso",
                                     extension_keys: %i[presentation html],
                                     bare: nil,
                                     sectionsplit: "true",
                                     datauriimage: true,
                                     agree_to_terms: true)
      f = "spec/fixtures/test_sectionsplit.html_collection"
      expect(File.exist?("#{f}/index.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.0.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.1.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.2.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.3.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.4.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.5.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.6.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.7.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.8.html")).to be false
      expect(File.exist?("#{f}/test_sectionsplit.html.9.html")).to be false
      expect(File.exist?("#{f}/test_sectionsplit.html.10.html")).to be false
      expect(File.exist?("#{f}/_test_sectionsplit_attachments/LICENSE.TXT")).to be true
      f = Dir.glob("spec/fixtures/test_sectionsplit_*_files").first
      expect(File.exist?("#{f}/cover.html")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.0.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.1.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.2.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.3.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.4.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.5.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.6.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.7.xml")).to be true
      expect(File.exist?("#{f}/test_sectionsplit.html.8.xml")).to be false
      expect(File.exist?("#{f}/test_sectionsplit.html.9.xml")).to be false
      expect(File.exist?("#{f}/test_sectionsplit.html.10.xml")).to be false
      expect(File.exist?("#{f}/test_sectionsplit.html.html.yaml")).to be true
      m = /type="([^"]+)"/.match(File.read("#{f}/test_sectionsplit.html.0.xml"))
      file2 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.3.xml"))
      file2.xpath("//xmlns:emf").each(&:remove)
      expect(file2.at("//xmlns:p[@id = 'middletitle']")).not_to be_nil
      expect(file2.at("//xmlns:note[@id = 'middlenote']")).not_to be_nil
      expect(Xml::C14n.format(file2
       .at("//xmlns:eref[@bibitemid = '#{m[1]}_A']").to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <eref bibitemid="#{m[1]}_A" type="#{m[1]}">HE<localityStack><locality type="anchor"><referenceFrom>A</referenceFrom></locality></localityStack></eref>
        OUTPUT
      expect(Xml::C14n.format(file2
       .at("//xmlns:note[@id = 'N1']//xmlns:eref[@bibitemid = '#{m[1]}_R1']")
        .to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <eref bibitemid="#{m[1]}_R1" type="#{m[1]}">SHE<localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></eref>
        OUTPUT
      expect(Xml::C14n.format(file2
       .at("//xmlns:note[@id = 'N2']//xmlns:eref[@bibitemid = '#{m[1]}_R1']")
        .to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <eref bibitemid="#{m[1]}_R1" type="#{m[1]}"><image src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/><localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></eref>
        OUTPUT
      expect(Xml::C14n.format(file2
       .at("//xmlns:note[@id = 'N3']//xmlns:link")
        .to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <link attachment="true" target="_test_sectionsplit_attachments/LICENSE.TXT">License A</link>
        OUTPUT
      expect(file2
       .at("//xmlns:bibitem[@id = 'R1']"))
        .to be_nil
      expect(Xml::C14n.format(file2
       .at("//xmlns:bibitem[@id = '#{m[1]}_A']").to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <bibitem id="#{m[1]}_A" type="internal">
          <docidentifier type="repository">#{m[1]}/A</docidentifier>
          </bibitem>
        OUTPUT
      expect(Xml::C14n.format(file2
       .at("//xmlns:bibitem[@id = '#{m[1]}_R1']").to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <bibitem id="#{m[1]}_R1" type="internal">
          <docidentifier type="repository">#{m[1]}/R1</docidentifier>
          </bibitem>
        OUTPUT
      expect(Xml::C14n.format(file2
       .at("//xmlns:svgmap[1]").to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
          <svgmap><figure>
          <image src="" mimetype="image/svg+xml" height="auto" width="auto">
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" id="Layer_1_000000000" x="0px" y="0px" viewBox="0 0 595.28 841.89" style="enable-background:new 0 0 595.28 841.89;" xml:space="preserve">
                 <image style="overflow:visible;" width="1" height="1" xlink:href="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/>
              <a href="A">A</a>
              <a href="B">B</a>
            </svg>
            </image>
            <target href="B">
              <eref type="#{m[1]}" bibitemid="#{m[1]}_R1">R1<localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></eref>
            </target>
          </figure>
          <target href="A"><eref bibitemid="#{m[1]}_A" type="#{m[1]}">A<localityStack><locality type="anchor"><referenceFrom>A</referenceFrom></locality></localityStack></eref></target><target href="B"><eref bibitemid="#{m[1]}_B" type="#{m[1]}">B<localityStack><locality type="anchor"><referenceFrom>B</referenceFrom></locality></localityStack></eref></target></svgmap>
        OUTPUT
      expect(Xml::C14n.format(file2
       .at("//xmlns:svgmap[2]").to_xml))
        .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
               <svgmap><figure>
           <image src="" mimetype="image/svg+xml" height="auto" width="auto">
           <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" id="Layer_1_000000000" x="0px" y="0px" viewBox="0 0 595.28 841.89" style="enable-background:new 0 0 595.28 841.89;" xml:space="preserve">
                 <image style="overflow:visible;" width="1" height="1" xlink:href="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/>
             <a href="P">P</a>
           </svg></img>
          </figure><target href="P"><eref bibitemid="#{m[1]}_P" type="#{m[1]}">P<localityStack><locality type="anchor"><referenceFrom>P</referenceFrom></locality></localityStack></eref></target></svgmap>
        OUTPUT
      expect(file2.at("//xmlns:preface")).to be_nil
      expect(file2.at("//xmlns:sections/xmlns:clause")).not_to be_nil
      expect(file2.at("//xmlns:annex")).to be_nil
      expect(file2.at("//xmlns:indexsect")).to be_nil
      #     file4 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.4.xml"))
      #     expect(Xml::C14n.format(file4
      #      .at("//xmlns:bibitem[@id = '#{m[1]}_R1']").to_xml))
      #       .to be_equivalent_to Xml::C14n.format(<<~OUTPUT)
      # <bibitem id="#{m[1]}_R1">
      #   <formattedref><em><span class="stddocTitle">Hello</span></em>.</formattedref>
      #   <docidentifier>R1</docidentifier>
      #   <biblio-tag>R1, </biblio-tag>
      # </bibitem>
      #       OUTPUT
      file6 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.6.xml"))
      expect(file6.at("//xmlns:preface")).to be_nil
      expect(file6.at("//xmlns:sections/xmlns:clause")).to be_nil
      expect(file6.at("//xmlns:annex")).not_to be_nil
      expect(file6.at("//xmlns:indexsect")).to be_nil
      expect(File.read("#{f}/test_sectionsplit.html.html.yaml"))
        .to be_equivalent_to <<~OUTPUT
          ---
          directives:
          - presentation-xml
          - bare-after-first
          bibdata:
            title:
              type: title-main
              language:
              content: ISO Title
            type: collection
            docid:
              type: ISO
              id: ISO 1
          manifest:
            level: collection
            title: Collection
            docref:
            - fileref: test_sectionsplit.html.0.xml
              identifier: Contents
            - fileref: test_sectionsplit.html.1.xml
              identifier: abstract
            - fileref: test_sectionsplit.html.2.xml
              identifier: introduction
            - fileref: test_sectionsplit.html.4.xml
              identifier: 1 Normative References
            - fileref: test_sectionsplit.html.3.xml
              identifier: 2 Clause 4
            - fileref: test_sectionsplit.html.5.xml
              identifier: Annex A (normative)  Annex (informative)
            - fileref: test_sectionsplit.html.6.xml
              identifier: Annex B (normative)  Annex 2
            - fileref: test_sectionsplit.html.7.xml
              identifier: Bibliography

        OUTPUT
      FileUtils.rm_f "tmp_test_sectionsplit.presentation.xml"
    end

    it "YAML collection with multiple documents sectionsplit (source document for links)" do
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_sectionsplit.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{INPATH}/ISO_17301-1_2016_index.html")).to be false
      expect(File.exist?("#{OUTPATH}/ISO_17301-1_2016_index.html")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO Collection 1"
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml.0.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml.2.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/_dummy_attachments/LICENSE1.TXT")).to be true
      rice = File.read("#{OUTPATH}/rice-en.final.xml.1.html")
      expect(rice).to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      expect(rice).to include %(It is not applicable to cooked rice products, which are not discussed in <a href="rice-en.final.xml.2.html#anotherclause_ISO_17301-1_2016_ISO_17301-1_2016_2_This_is_another_clause"><span class="citesec">Clause 2</span></a> or <a href="rice-en.final.xml.3.html#thirdclause_ISO_17301-1_2016_ISO_17301-1_2016_3_This_is_another_clause"><span class="citesec">Clause 3</span></a>.</p>)
      # resolves SVG references to Express
      expect(rice).to match %r{<a xlink:href="dummy.html#express-schema_E1_ISO_17302">\s+<rect x="324\.69" y="450\.52"}m
      expect(rice).to match %r{<a xlink:href="dummy.html#express-schema_E2_ISO_17302">\s+<rect x="324\.69" y="528\.36"}m
      expect(rice).to match %r{<a xlink:href="mn://action_schema">\s+<rect x="123\.28" y="273\.93"}m
      # demonstrate that erefs are removed if they point to another document in the repository,
      # but that document is not supplied
      expect(rice).to match %r{This document uses schemas E0/A0, <a href="dummy\.html#express-schema_E1_ISO_17302">E1/A1</a> and <a href="dummy\.html#express-schema_E2_ISO_17302">express-schema/E2</a>.}
      expect(rice).to include %(This document is also unrelated to <a href="dummy.html#what">)
      xml = Nokogiri::XML(File.read("#{OUTPATH}/rice-en.final.xml.1.presentation.xml"))
      p = xml.xpath("//xmlns:sections//xmlns:p")[4]
      p.delete("id")
      expect(p.to_xml).to be_equivalent_to <<~OUTPUT
        <p>This document is updated in <link target="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</link>.</p>
      OUTPUT
      FileUtils.rm_rf of
    end

    it "YAML collection with multiple documents sectionsplit (target document for links)" do
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_target_sectionsplit.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{INPATH}/ISO_17302_2016_index.html")).to be false
      expect(File.exist?("#{OUTPATH}/ISO_17302_2016_index.html")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO Collection 1"
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be false
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be false
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml.0.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml.1.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml.2.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %(It is not applicable to cooked rice products, which are not discussed in <a href="#anotherclause_ISO_17301-1_2016"><span class="citesec">Clause 2</span></a> or <a href="#thirdclause_ISO_17301-1_2016"><span class="citesec">Clause 3</span></a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # and point to the right sectionsplit file
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %(This document is also unrelated to <a href="dummy.xml.3.html#what">)
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %{This document is also unrelated to <a href="dummy.xml.3.html#what">current-metanorma-collection/ISO 17302:2016 3 What?</a>.</p><p id="_001_ISO_17301-1_2016">This document uses schemas E0/A0, <a href="dummy.xml.2.html#A1_ISO_17302_2016_ISO_17302_2016_2">E1/A1</a> and <a href="dummy.xml.4.html#E2_ISO_17302_2016_ISO_17302_2016_4">E2</a>.</p>}
      FileUtils.rm_rf of
    end

    it "YAML collection with single document sectionsplit" do
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_sectionsplit_solo.yml"
      of = OUTPATH.to_s
      FileUtils.rm_rf "#{OUTPATH}/index.html"
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/ISO_17301-1_2016_index.html")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO Collection 1"
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml.0.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml.2.html"))
        .to be true
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to include %(This document is updated in <b>** Unresolved reference to document ISO 17301-1:2016/Amd.1:2017 from eref</b>.</p>)
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to include %(This document uses schemas E0/A0, E1/A1 and express-schema/E2.)
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to include %(This document is also unrelated to <a href="dummy.html#what">)
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
      of = OUTPATH
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
      Metanorma::Collection.parse file
      expect(File.exist?("#{INPATH}/document-1/document-1.xml")).to be true
      time = File.mtime("#{INPATH}/document-1/document-1.xml")
      Metanorma::Collection.parse file
      expect(File.mtime("#{INPATH}/document-1/document-1.xml")).to be_within(0.1).of time
      a = File.read(file).sub(/- documents-inline/, "- recompile-xml\n- documents-inline")
      File.open(file, "w") { |x| x.write(a) }
      Metanorma::Collection.parse file
      expect(File.mtime("#{INPATH}/document-1/document-1.xml")).not_to be_within(0.1).of time
    end
  end

  context "Word collection" do
    it "builds Word collection, no coverpages" do
      file = "#{INPATH}/wordcollection.yml"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation doc],
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
      expect(Xml::C14n.format(cleanup_guid(cleanup_id(output))))
        .to be_equivalent_to Xml::C14n.format(cleanup_guid(expected))
      FileUtils.rm_rf of
    end

    it "builds Word collection, coverpages" do
      file = "#{INPATH}/wordcollection_cover.yml"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation doc],
        output_folder: of,
        compile: {
          install_fonts: false,
        },
      )
      output = File.read("#{OUTPATH}/collection.doc")
      expected = File.read("#{INPATH}/collection1.doc")
      output.sub!(%r{</html>.*$}m, "</html>").sub!(%r{^.*<html }m, "<html ")
        .sub!(%r{<style>.+</style>}m, "<style/>")
      expect(Xml::C14n.format(cleanup_guid(cleanup_id(output))))
        .to be_equivalent_to Xml::C14n.format(cleanup_guid(expected))
      FileUtils.rm_rf of
    end
  end

  context "bilingual document" do
    it "YAML collection" do
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.rm_f "#{OUTPATH}/collection1.err.html"
      file = "#{INPATH}/bilingual.yml"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        output_folder: of,
        # coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          install_fonts: false,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      concat_text = cleanup_guid(read_and_cleanup("#{INPATH}/bilingual.presentation.xml"))
      concat_file = cleanup_guid(read_and_cleanup("#{OUTPATH}/collection.presentation.xml"))
      x = Nokogiri::XML(concat_file).at(".//xmlns:doc-container")
      x.at(".//*[local-name() = 'metanorma-extension']")&.remove
      x.at(".//*[local-name() = 'localized-strings']")&.remove
      a = Xml::C14n.format(cleanup_guid(x.to_xml))
        .sub(%r{xlink:href=['"]data:image/gif;base64,[^"']*['"]},
             "xlink:href='data:image/gif;base64,_'")
        .gsub(%r{<localized-strings>.*?</localized-strings>}m, "<localized-strings/>")
      b = Xml::C14n.format(concat_text)
          .sub(%r{xlink:href=['"]data:image/gif;base64[^"']*['"]},
               "xlink:href='data:image/gif;base64,_'")
      expect(a).to be_equivalent_to b
    end
  end

  private

  def cleanup_guid(content)
    content
      .gsub(%r{cid:#{GUID}}o, "cid:_")
      .gsub(%r{ id="_#{GUID}"}o, ' id="_"')
      .gsub(%r{ target="_#{GUID}"}o, ' name="_"')
      .gsub(%r{ source="_#{GUID}"}o, ' source="_"')
      .gsub(%r{ original-id="_#{GUID}"}o, ' original-id="_"')
      .gsub(%r{ name="_#{GUID}"}o, ' name="_"')
      .gsub(%r{_Toc[0-9]{9}}o, "_Toc")
  end

  def read_and_cleanup(file)
    content = File.read(file, encoding: "UTF-8").gsub(
      /(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s
    )
    cleanup_id content
  end

  def cleanup_id(content)
    content.gsub(/(?<=<p id=")[^"]+/, "")
      .gsub(%r{data:image/svg\+xml[^<"']+}, "data:image/svg+xml")
      .gsub(%r{data:image/png[^<"']+}, "data:image/png")
      .gsub(/ schema-version="[^"]+"/, "")
      .gsub(%r{<identifier>#{GUID}</identifier>}o, "<identifier>_</identifier>")
  end

  def mock_render
    original_add = Metanorma::Collection::Renderer.method(:render)
    allow(Metanorma::Collection::Renderer)
      .to receive(:render) do |col, opts|
      original_add.call(col, opts.merge(compile: { install_fonts: false }))
    end
  end
end
