# frozen_string_literal: true

RSpec.describe Metanorma::Collection do
  context "parse" do
    it "YAML collection" do
      xml_file = "spec/fixtures/collection/collection1.xml"
      mc = Metanorma::Collection.parse "spec/fixtures/collection/collection1.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(xml)).to be_equivalent_to xml_content
    end

    it "YAML collection with docs inline" do
      xml_file = "spec/fixtures/collection/collection_docinline.xml"
      mc = Metanorma::Collection
        .parse("spec/fixtures/collection/collection_docinline.yml")
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      expect(cleanup_id(xml)).to be_equivalent_to read_and_cleanup(xml_file)
    end

    it "XML collection" do
      file = "spec/fixtures/collection/collection1.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
    end

    it "XML collection with docs inline" do
      file = "spec/fixtures/collection/collection_docinline.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
    end
  end

  context "render html & build doc, pdf, xml files from" do
    it "YAML collection" do # rubocop:disable metrics/blocklength
      file = "spec/fixtures/collection/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = "spec/fixtures/ouput"
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml doc],
        output_folder: of,
        coverpage: "spec/fixtures/collection/collection_cover.html"
      )
      expect(File.exist?("spec/fixtures/ouput/index.html")).to be true
      expect(File.read("spec/fixtures/ouput/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1</h1>"
      expect(File.exist?("spec/fixtures/ouput/dummy.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.presentation.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.presentation.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.presentation.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.presentation.xml")).to be true
      FileUtils.rm_rf of
    end

    it "YAML collection with documents inline" do # rubocop:disable metrics/blocklength
      file = "spec/fixtures/collection/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = "spec/fixtures/ouput"
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml doc],
        output_folder: of,
        coverpage: "spec/fixtures/collection/collection_cover.html"
      )
      expect(File.exist?("spec/fixtures/ouput/index.html")).to be true
      expect(File.read("spec/fixtures/ouput/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1</h1>"
      expect(File.exist?("spec/fixtures/ouput/dummy.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/dummy.presentation.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-amd.final.presentation.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice-en.final.presentation.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.html")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.doc")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.pdf")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.xml")).to be true
      expect(File.exist?("spec/fixtures/ouput/rice1-en.final.presentation.xml")).to be true
      FileUtils.rm_rf of
    end
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
  end
end
