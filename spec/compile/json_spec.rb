require "spec_helper"
require "json"
require "open3"
require "tmpdir"

RSpec.describe Metanorma::Compile do
  let(:out) { Dir.mktmpdir("json-compile") }

  after { FileUtils.remove_entry(out) }

  # A subprocess keeps the flavor-gem load single-shot (see mko_spec).
  def compile_json(input)
    script = <<~RUBY
      require "metanorma"
      c = Metanorma::Compile.new
      c.compile(ARGV[0], type: "iso", extension_keys: [:json],
                output_dir: ARGV[1], no_install_fonts: true)
      exit(c.errors.empty? ? 0 : 1)
    RUBY
    ok, status = Open3.capture2e(RbConfig.ruby, "-e", script, input, out)
    expect(status.success?).to be(true), ok
    JSON.parse(File.read(Dir[File.join(out, "*.json")].first))
  end

  def clause_titles(node)
    return [] unless node.is_a?(Hash)

    own = node["type"] == "clause" ? [node.dig("attrs", "title")] : []
    own + Array(node["content"]).flat_map { |child| clause_titles(child) }
  end

  before do
    skip "metanorma-document not in the bundle" unless begin
      require "metanorma/document"
      true
    rescue LoadError
      false
    end
  end

  it "registers json beside mko as an opt-in harness format" do
    expect(described_class::HARNESS_OUTPUT_FORMATS)
      .to include(json: "json", mko: "mko")
  end

  it "serializes semantic XML input as Metanorma JSON" do
    doc = compile_json("spec/fixtures/mko/iso-semantic.xml")

    expect(doc["attrs"]).to include("flavor" => "iso", "type" => "semantic")
    expect(clause_titles(doc)).to include("Scope")
  end

  it "serializes AsciiDoc input, which writes no XML to disk" do
    adoc = File.join(out, "sample.adoc")
    File.write(adoc, <<~ADOC)
      = Sample Title
      :docnumber: 1000
      :doctype: international-standard

      == Scope

      Hello world.

      == Normative references

      Some clause text.

      == General

      More text.
    ADOC

    doc = compile_json(adoc)

    expect(clause_titles(doc)).to include("Scope", "General")
  end
end
