# frozen_string_literal: true

RSpec.describe Metanorma::Collection do
  it 'parse YAML collection' do
    xml_file = 'spec/fixtures/collection/collection1.xml'
    mc = Metanorma::Collection.parse 'spec/fixtures/collection/collection1.yml'
    xml = mc.to_xml
    File.write xml_file, xml, encoding: 'UTF-8' unless File.exist? xml_file
    expect(mc).to be_instance_of Metanorma::Collection
    xml_content = File.read(xml_file, encoding: 'UTF-8').gsub(
      /(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s
    ).gsub(/(?<=<p id=")[^"]+/, '')
    expect(xml.gsub(/(?<=<p id=")[^"]+/, '')).to be_equivalent_to xml_content
  end
end
