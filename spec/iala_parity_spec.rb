require "spec_helper"
require "yaml"
require "fileutils"

# Render-parity catalogue for the iala taste against its iho base
# (metanorma-taste#248, metanorma#699). Each of the taste's doctypes has a
# fixture in spec/fixtures/iala/ and an entry in parity_catalogue.yml. The
# fixture is rendered to html through the iala taste and, as the reference,
# through the iho flavor with the doctype's base doctype. Features the iho
# render has and the iala render lacks are the entry's `gaps`: they are
# recorded, not fixed.
IALA_FIXTURES = File.expand_path("fixtures/iala", __dir__)
IALA_CATALOGUE = YAML.safe_load_file(
  File.join(IALA_FIXTURES, "parity_catalogue.yml"),
)

# Element probes on the rendered html; a gap is a probe the iho render
# matches and the iala render does not.
IALA_FEATURES = {
  "table" => /<table\b/,
  "formula" => /<math\b|class="formula"|MathML/,
  "note" => /class="Note"/,
  "example" => /class="example"/,
  "list" => /<ul\b/,
  "xref" => /<a href="#(?:tab1|f1)"/,
}.freeze

RSpec.describe Metanorma::Compile do # rubocop:disable RSpec/SpecFilePathFormat
  let(:declared) do
    Metanorma::TasteRegister.get_config("iala").doctypes
      .map { |d| d.taste.to_s }
  end

  def render_html(adoc, type, doctype, dir)
    FileUtils.mkdir_p(dir)
    src = File.join(dir, "doc.adoc")
    File.write(src, File.read(adoc)
      .sub(/^:doctype: .*$/, ":doctype: #{doctype}"))
    described_class.new.compile(
      src, type: type, extension_keys: [:html], install_fonts: false
    )
    File.read(File.join(dir, "doc.html"))
  end

  it "declares eleven doctypes in the iala taste" do
    expect(declared.size).to eq(11)
  end

  it "catalogues exactly the doctypes the iala taste declares" do
    expect(IALA_CATALOGUE.keys).to match_array(declared)
  end

  it "has a fixture for every catalogued doctype" do
    paths = IALA_CATALOGUE.keys
      .map { |d| File.join(IALA_FIXTURES, "#{d}.adoc") }
    expect(paths).to all(satisfy { |path| File.exist?(path) })
  end

  IALA_CATALOGUE.each do |doctype, entry|
    describe doctype do
      let(:adoc) { File.join(IALA_FIXTURES, "#{doctype}.adoc") }

      it "is catalogued as rendering to html" do
        expect(entry["html"]).to eq("pass")
      end

      it "renders to html through the iala taste" do
        html = render_html(adoc, "iala", doctype, "iala-#{doctype}")
        expect(html).to include("<html")
      end

      it "lists the features the iho base renders and iala does not" do
        iala = render_html(adoc, "iala", doctype, "iala-#{doctype}")
        iho = render_html(adoc, "iho", entry["base"], "iho-#{doctype}")
        gaps = IALA_FEATURES
          .select { |_, re| iho.match?(re) && !iala.match?(re) }.keys
        expect(gaps).to eq(entry["gaps"])
      end
    end
  end
end
