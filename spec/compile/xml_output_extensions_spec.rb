require_relative "../spec_helper"

RSpec.describe "output extensions declared in semantic XML" do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def semantic_xml(output_extensions = nil)
    ext = if output_extensions
            "<metanorma-extension><presentation-metadata>" \
              "<output-extensions>#{output_extensions}</output-extensions>" \
              "</presentation-metadata></metanorma-extension>"
          end
    <<~XML
      <metanorma xmlns="https://www.metanorma.org/ns/standoc" flavor="iso">
        <bibdata type="standard"><title>Probe</title></bibdata>
        #{ext}
        <sections><clause><p>Text.</p></clause></sections>
      </metanorma>
    XML
  end

  def write_file(content, name = "probe.xml")
    file = File.join(@dir, name)
    File.write(file, content)
    file
  end

  def extract(content, options = {}, name = "probe.xml")
    Metanorma::Compile.new
      .send(:extract_options, write_file(content, name), options)
  end

  it "selects the extensions listed in the document" do
    expect(extract(semantic_xml("xml,html"))[:extension_keys])
      .to eq %i[xml html]
  end

  it "accepts a space after each comma" do
    expect(extract(semantic_xml("xml, html"))[:extension_keys])
      .to eq %i[xml html]
  end

  it "gives priority to the extensions passed on the command line" do
    opts = extract(semantic_xml("xml,html"), extension_keys: [:doc])
    expect(opts[:extension_keys]).to eq [:doc]
  end

  it "applies no filter when the document has no output-extensions" do
    expect(extract(semantic_xml)[:extension_keys]).to be_nil
  end

  it "applies no filter when the document lists all" do
    expect(extract(semantic_xml("all"))[:extension_keys]).to be_nil
  end

  it "applies no filter when output-extensions is empty" do
    expect(extract(semantic_xml("  "))[:extension_keys]).to be_nil
  end

  it "ignores output-extensions of a nested document" do
    nested = semantic_xml.sub(
      "<sections>",
      "<attachment>#{semantic_xml('xml')}</attachment><sections>",
    )
    expect(extract(nested)[:extension_keys]).to be_nil
  end

  it "sets no extensions key for non-XML content" do
    ret = Metanorma::Compile.new
      .extract_xml_options("= Title\n:mn-output-extensions: xml\n")
    expect(ret).not_to have_key(:extensions)
  end

  it "keeps the AsciiDoc header extensions for .adoc input" do
    adoc = <<~ADOC
      = Probe
      :docnumber: 1
      :mn-document-class: iso
      :mn-output-extensions: xml,html

      Text.
    ADOC
    expect(extract(adoc, {}, "probe.adoc")[:extension_keys])
      .to eq %i[xml html]
  end
end
