# frozen_string_literal: true

RSpec.describe Metanorma::Collection do # rubocop:disable Metrics/BlockLength
  it "parse YAML collection" do
    xml_file = "spec/fixtures/collection/collection1.xml"
    mc = Metanorma::Collection.parse "spec/fixtures/collection/collection1.yml"
    xml = mc.to_xml
    File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
    expect(mc).to be_instance_of Metanorma::Collection
    xml_content = read_and_cleanup(xml_file)
    expect(cleanup_id(xml)).to be_equivalent_to xml_content
  end

  it "parse YAML collection with docs inline" do
    xml_file = "spec/fixtures/collection/collection_docinline.xml"
    mc = Metanorma::Collection
      .parse("spec/fixtures/collection/collection_docinline.yml")
    xml = mc.to_xml
    File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
    expect(mc).to be_instance_of Metanorma::Collection
    expect(cleanup_id(xml)).to be_equivalent_to read_and_cleanup(xml_file)
  end

  it "parse XML collection" do
    file = "spec/fixtures/collection/collection1.xml"
    mc = Metanorma::Collection.parse file
    expect(mc).to be_instance_of Metanorma::Collection
    xml = cleanup_id File.read(file, encoding: "UTF-8")
    expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
  end

  it "parse XML collection with docs inline" do
    file = "spec/fixtures/collection/collection_docinline.xml"
    mc = Metanorma::Collection.parse file
    expect(mc).to be_instance_of Metanorma::Collection
    xml = cleanup_id File.read(file, encoding: "UTF-8")
    expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
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
