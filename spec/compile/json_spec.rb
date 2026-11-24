require "spec_helper"
require "json"
require "open3"
require "tmpdir"

RSpec.describe Metanorma::Compile do
  let(:out) { Dir.mktmpdir("json-compile") }

  after { FileUtils.remove_entry(out) }

  # A subprocess keeps the flavor-gem load single-shot (see mko_spec).
  def run_compile(input, type)
    script = <<~RUBY
      require "metanorma"
      c = Metanorma::Compile.new
      c.compile(ARGV[0], type: ARGV[2], extension_keys: [:json],
                output_dir: ARGV[1], no_install_fonts: true)
      exit(c.errors.empty? ? 0 : 1)
    RUBY
    Open3.capture2e(RbConfig.ruby, "-e", script, input, out, type)
  end

  def compile_json(input, type: "iso")
    log, status = run_compile(input, type)
    expect(status.success?).to be(true), log
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

  it "reports a model Mirror cannot serialize instead of writing null" do
    adoc = File.join(out, "generic.adoc")
    File.write(adoc, "= Sample\n:docnumber: 1\n:novalid:\n\n== Scope\n\nHi.\n")

    log, status = run_compile(adoc, "generic")

    expect(status.success?).to be(false)
    expect(log).to include("cannot serialize the generic document model")
    expect(Dir[File.join(out, "*.json")]).to be_empty
  end
end
