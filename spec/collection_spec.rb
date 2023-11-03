# frozen_string_literal: true

INPATH = "spec/fixtures/collection"
OUTPATH = "spec/fixtures/ouput"

RSpec.describe Metanorma::Collection do
  context "parse" do
    it "YAML collection" do
      mock_pdf
      xml_file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(xml)).to be_equivalent_to xml_content
    end

    it "YAML collection with docs inline" do
      mock_pdf
      xml_file = "#{INPATH}/collection_docinline.xml"
      mc = Metanorma::Collection
        .parse("#{INPATH}/collection_docinline.yml")
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      expect(xmlpp(cleanup_id(xml)))
        .to be_equivalent_to xmlpp(read_and_cleanup(xml_file))
    end

    it "XML collection" do
      mock_pdf
      file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
    end

    it "XML collection with docs inline" do
      mock_pdf
      file = "#{INPATH}/collection_docinline.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(xmlpp(cleanup_id(mc.to_xml))).to be_equivalent_to xmlpp(xml)
    end
  end

  context "render html & build doc, pdf, xml files from" do
    it "YAML collection" do # rubocop:disable metrics/blocklength
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err"
      FileUtils.rm_f "#{OUTPATH}/collection1.err"
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
          no_install_fonts: true,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      concat_text = read_and_cleanup "#{INPATH}/collection_full.xml"
      concat_file = read_and_cleanup "#{OUTPATH}/collection.xml"
      expect(xmlpp(concat_file.gsub("><", ">\n<"))
        .sub(%r{xlink:href=['"]data:image/gif;base64,[^']*'},
             "xlink:href='data:image/gif;base64,_'"))
        .to be_equivalent_to xmlpp(concat_text.gsub("><", ">\n<"))
          .sub(%r{xlink:href=['"]data:image/gif;base64[^']*'},
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
      expect(concat_text_doc_xml.at("//xmlns:xref/@target").text)
        .to be_equivalent_to "_scope"
      expect(conact_file_doc_xml.xpath("//i:xref/@target", "i" => "https://www.metanorma.org/ns/iso")[-1].text)
        .to be_equivalent_to "_scope_ISO_17301-1_2016"
      expect(concat_text_doc_xml.at("//xmlns:strong/@style").text)
        .to be_equivalent_to "background: url(#svg1); foreground: url(_001); middleground: url(#fig1);"
      expect(conact_file_doc_xml.at("//i:strong/@style", "i" => "https://www.metanorma.org/ns/iso").text)
        .to be_equivalent_to "background: url(#svg1_ISO_17301-1_2016); foreground: url(_001); middleground: url(#fig1_ISO_17301-1_2016);"

      expect(File.exist?("#{INPATH}/collection1.err")).to be true
      expect(File.read("#{INPATH}/collection1.err", encoding: "utf-8"))
        .to include "Missing:​express-schema:​E0"
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1"
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO 17301-1:2016/Amd.1:2017"
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
      FileUtils.rm_rf of
    end

    it "extracts metadata from collection for Liquid" do
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      cr = Metanorma::CollectionRenderer
        .render(col,
                format: %i[presentation html xml],
                output_folder: of,
                coverpage: "#{INPATH}/collection_cover.html",
                compile: {
                  no_install_fonts: true,
                })
      expect(cr.isodoc.meta.get[:docrefs])
        .to be_equivalent_to [
          { "identifier" => "ISO 17301-1:2016", "file" => "rice-en.final.html",
            "title" => "Cereals and pulses&#x2009;&#x2014;&#x2009;" \
                       "Specifications and test methods&#x2009;&#x2014;" \
                       "&#x2009;Rice (Final)", "level" => nil },
          { "identifier" => "ISO 17302", "file" => "dummy.html",
            "title" => "Dummy document", "level" => nil },
          { "identifier" => "ISO 1701:1974", "file" => "rice1-en.final.html",
            "title" => "Test conditions for milling machines with table of " \
                       "variable height, with horizontal or vertical spindle",
            "level" => nil },
          { "identifier" => "ISO 17301-1:2016/Amd.1:2017",
            "file" => "rice-amd.final.html",
            "title" => "Specification and test methods&#x2009;&#x2014;&#x2009;" \
                       "Rice&#x2009;&#x2014;&#x2009;Mass fraction of " \
                       "extraneous matter, milled rice (nonglutinous), sample " \
                       "dividers and recommendations relating to storage and " \
                       "transport conditions", "level" => nil },
          { "identifier" => "action_schemaexpg1.svg",
            "file" => "pics/action_schemaexpg1.svg", "title" => nil,
            "level" => nil },
          { "identifier" => "rice_image1.png",
            "file" => "assets/rice_image1.png",
            "title" => nil, "level" => nil },
        ]
      expect(cr.isodoc.meta.get[:navigation])
        .to be_equivalent_to <<~OUTPUT
          <ul>
          <li>ISO Collection</li>
          <ul>
          <li>Standards</li>
          <ul>
          <li><a href="rice-en.final.html">ISO&nbsp;17301-1:2016</a></li>
          <li><a href="dummy.html">ISO&nbsp;17302</a></li>
          <li><a href="rice1-en.final.html">ISO&nbsp;1701:1974</a></li>
          </ul>
          </ul>
          <ul>
          <li>Amendments</li>
          <ul><li><a href="rice-amd.final.html">ISO 17301-1:2016/Amd.1:2017</a></li></ul>
          </ul>
          <ul>
          <li>Attachments</li>
          <ul>
          <li><a href="pics/action_schemaexpg1.svg">action_schemaexpg1.svg</a></li>
          <li><a href="assets/rice_image1.png">rice_image1.png</a></li>
          </ul>
          </ul>
          </ul>
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
        .to be_equivalent_to ({ title: "ISO Collection",
                                children: [
                                  { title: "Standards",
                                    docrefs: "<ul><li><a href=\"rice-en.final.html\">ISO&nbsp;17301-1:2016</a></li><li><a href=\"dummy.html\">ISO&nbsp;17302</a></li><li><a href=\"rice1-en.final.html\">ISO&nbsp;1701:1974</a></li></ul>" },
                                  { title: "Amendments",
                                    docrefs: "<ul><li><a href=\"rice-amd.final.html\">ISO 17301-1:2016/Amd.1:2017</a></li></ul>" },
                                  { title: "Attachments",
                                    docrefs: "<ul><li><a href=\"pics/action_schemaexpg1.svg\">action_schemaexpg1.svg</a></li><li><a href=\"assets/rice_image1.png\">rice_image1.png</a></li></ul>" },
                                ] })
    end

    it "uses presentation XML directive, markup in identifiers" do # rubocop:disable metrics/blocklength
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err"
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
          no_install_fonts: true,
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

    it "YAML collection with documents inline" do # rubocop:disable metrics/blocklength
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
          no_install_fonts: true,
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

    it "YAML collection with multiple documents sectionsplit (source document for links)" do # rubocop:disable metrics/blocklength
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
          no_install_fonts: true,
        },
      )
      expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{INPATH}/ISO 17301-1_2016_index.html")).to be false
      expect(File.exist?("#{OUTPATH}/ISO 17301-1_2016_index.html")).to be true
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
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO</span> <span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # but that document is not supplied
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to match %r{This document uses schemas E0/A0, <a href="#.{8}_express-schema_E1_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope">E1/A1</a> and <a href="#.{8}_express-schema_E2_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope">E2/A2</a>\.}
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(This document is also unrelated to <a href="ISO 17302_index.html#what">)
      xml = Nokogiri::XML(File.read("#{OUTPATH}/rice-en.final.xml.1.presentation.xml"))
      p = xml.xpath("//xmlns:sections//xmlns:p")[4]
      p.delete("id")
      expect(p.to_xml).to be_equivalent_to <<~OUTPUT
        <p>This document is updated in <link target="rice-amd.final.html"><span class="stdpublisher">ISO</span> <span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</link>.</p>
      OUTPUT
      FileUtils.rm_rf of
    end

    it "YAML collection with multiple documents sectionsplit (target document for links)" do # rubocop:disable metrics/blocklength
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
          no_install_fonts: true,
        },
      )
      expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{INPATH}/ISO 17301-1_2016_index.html")).to be false
      expect(File.exist?("#{OUTPATH}/ISO 17301-1_2016_index.html")).to be true
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
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO</span> <span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # but that document is not supplied
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to match %r{This document uses schemas E0/A0, <a href="#.{8}_express-schema_E1_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope">E1/A1</a> and <a href="#.{8}_express-schema_E2_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope">E2/A2</a>\.}
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(This document is also unrelated to <a href="ISO 17302_index.html#what">)
      xml = Nokogiri::XML(File.read("#{OUTPATH}/rice-en.final.xml.1.presentation.xml"))
      p = xml.xpath("//xmlns:sections//xmlns:p")[4]
      p.delete("id")
      expect(p.to_xml).to be_equivalent_to <<~OUTPUT
        <p>This document is updated in <link target="rice-amd.final.html"><span class="stdpublisher">ISO</span> <span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</link>.</p>
      OUTPUT
      FileUtils.rm_rf of
    end

    it "YAML collection with single document sectionsplit" do # rubocop:disable metrics/blocklength
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_sectionsplit_solo.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/ISO 17301-1_2016_index.html")).to be false
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
        .to include %(This document uses schemas E0/A0, E1/A1 and E2/A2.)
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(This document is also unrelated to <a href="ISO 17302_index.html#what">)
      FileUtils.rm_rf of
    end
  end

  it "disambiguates destination filenames" do
    file = "#{INPATH}/collection.dup.yml"
    of = OUTPATH
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "#{INPATH}/collection_cover.html",
      compile: {
        no_install_fonts: true,
      },
    )
    expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.1.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.2.xml")).to be true
    FileUtils.rm_rf of
  end

  it "skips indexing of files in coverpage on request" do
    file = "#{INPATH}/collection.dup.yml"
    of = OUTPATH
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "#{INPATH}/collection_cover.html",
      compile: {
        no_install_fonts: true,
      },
    )
    index = File.read("#{OUTPATH}/index.html")
    expect(index).to include "ISO&nbsp;44001"
    expect(index).not_to include "ISO&nbsp;44002"
    expect(index).to include "ISO&nbsp;44003"
    FileUtils.rm_rf of
  end

  it "injects repository identifiers" do
    file = "#{INPATH}/collection1.norepo.yml"
    of = OUTPATH
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "#{INPATH}/collection_cover.html",
      compile: {
        no_install_fonts: true,
      },
    )
    index = File.read("#{OUTPATH}/rice-en.final.norepo.xml")
    expect(index).to include "Mass fraction of extraneous matter, milled rice " \
                             "(nonglutinous), sample dividers and " \
                             "recommendations relating to storage and " \
                             "transport conditions"
    # has successfully mapped identifier of ISO 17301-1:2016/Amd.1:2017 in
    # rice-en.final.norepo.xml to the file in the collection, and imported its bibdata
    FileUtils.rm_rf of
  end

  private

  def read_and_cleanup(file)
    content = File.read(file, encoding: "UTF-8").gsub(
      /(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s
    )
    cleanup_id content
  end

  # @param content [String]
  # @return [String]
  def cleanup_id(content)
    content.gsub(/(?<=<p id=")[^"]+/, "")
      .gsub(%r{data:image/svg\+xml[^<"']+}, "data:image/svg+xml")
      .gsub(%r{data:image/png[^<"']+}, "data:image/png")
      .gsub(/ schema-version="[^"]+"/, "")
  end
end
