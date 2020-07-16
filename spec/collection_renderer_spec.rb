RSpec.describe Metanorma::CollectionRenderer do
  it "Render HTML from XML collection" do
    file = "spec/fixtures/collection/collection1.xml"
    xml = File.read file, encoding: "UTF-8"
    of = "spec/fixtures/ouput"
    Metanorma::CollectionRenderer.render(
      xml, filename: file, format: [:html], output_folder: of,
      coverpage: "spec/fixtures/collection/collection_cover.html"
    )
    expect(File.exist?("spec/fixtures/ouput/index.html")).to be true
    expect(File.read("spec/fixtures/ouput/index.html", encoding: "UTF-8")).to include "<h1>ISO Collection 1</h1>"
    expect(File.exist?("spec/fixtures/ouput/dummy.html")).to be true
    expect(File.exist?("spec/fixtures/ouput/rice-amd.final.html")).to be true
    expect(File.exist?("spec/fixtures/ouput/rice-en.final.html")).to be true
    expect(File.exist?("spec/fixtures/ouput/rice1-en.final.html")).to be true
    FileUtils.rm_rf of
  end
end
