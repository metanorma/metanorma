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
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH
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
      concat_text = read_and_cleanup "#{INPATH}/collection_full.xml"
      concat_file = read_and_cleanup "#{OUTPATH}/collection.xml"
      expect(xmlpp(concat_file)
        .sub(%r{xlink:href='data:image/gif;base64,[^']*'},
             "xlink:href='data:image/gif;base64,_'"))
        .to be_equivalent_to xmlpp(concat_text)
          .sub(%r{src='xlink:href='data:image/gif;base64[^']*'},
               "xlink:href='data:image/gif;base64,_'")
      conact_file_doc_xml = Nokogiri::XML(concat_file)

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
      expect(File.exist?("#{INPATH}/collection1.err")).to be true
      expect(File.read("#{INPATH}/collection1.err", encoding: "utf-8"))
        .to include "Cannot find crossreference to document"
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1</h1>"
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO 17301-1:2016/Amd.1:2017"
      expect(File.exist?("#{OUTPATH}/pics/action_schemaexpg1.svg")).to be true
      expect(File.exist?("#{OUTPATH}/assets/rice_image1.png")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      # expect(File.exist?("#{OUTPATH}/dummy.doc")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.read("#{OUTPATH}/dummy.xml"))
        .not_to be_equivalent_to File.read("#{OUTPATH}/dummy.presentation.xml")
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice1-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml")).to be true
      FileUtils.rm_rf of
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
        .to include "<h1>ISO Collection 1</h1>"
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      # expect(File.exist?("#{OUTPATH}/dummy.doc")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice1-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml")).to be true
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
  end
end
