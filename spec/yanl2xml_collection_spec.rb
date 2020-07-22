RSpec.describe Metanorma::Yaml2XmlCollection do
  it 'convetr YAML collection to XML' do
    xml = Metanorma::Yaml2XmlCollection.convert(
      'spec/fixtures/collection/collection1.yml',
    )
    expect(xml.gsub(/(?<=<p id=")[^"]+/, '')).to be_equivalent_to File.read(
      'spec/fixtures/collection/collection1.xml', encoding: 'UTF-8'
    ).gsub(/(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s).
      gsub(/(?<=<p id=")[^"]+/, '')
  end
end
