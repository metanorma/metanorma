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
      begin
        c.compile(ARGV[0], type: ARGV[2], extension_keys: [:json],
                  output_dir: ARGV[1], no_install_fonts: true)
      rescue StandardError => e
        puts "RAISED: \#{e.class}"
        exit 2
      end
      puts "POOLED: \#{c.errors.inspect}"
      exit(c.errors.empty? ? 0 : 1)
    RUBY
    Open3.capture2e(RbConfig.ruby, "-e", script, input, out, type)
  end

  def compile_json(input, type: "iso")
    log, status = run_compile(input, type)
    expect(status.success?).to be(true), log
    JSON.parse(File.read(Dir[File.join(out, "*.json")].first),
               max_nesting: false)
  end

  def clause_titles(node)
    return [] unless node.is_a?(Hash)

    own = node["type"] == "clause" ? [node.dig("attrs", "title")] : []
    own + Array(node["content"]).flat_map { |child| clause_titles(child) }
  end

  def export_json_failing_with(error)
    require "metanorma/mirror"
    compile = described_class.new
    processor = instance_double(Metanorma::Processor, short: %i[iso])
    compile.instance_variable_set(:@processor, processor)
    pipeline = Metanorma::Mirror::Output::Pipeline
    allow(pipeline).to receive(:new).and_raise(error)
    compile.send(:export_json, "<metanorma/>",
                 out: File.join(out, "x.json"))
    compile.errors
  end

  def with_nested_clauses(depth)
    nested = (1..depth).map do |i|
      %(<clause id="_nested#{i}" obligation="normative">) \
        "<title>Level #{i}</title>"
    end
    File.read("spec/fixtures/mko/iso-semantic.xml")
      .sub("</sections>", "#{nested.join}#{'</clause>' * depth}</sections>")
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

  it "serializes clauses nested beyond the JSON default nesting limit" do
    input = File.join(out, "deep.xml")
    File.write(input, with_nested_clauses(60))

    doc = compile_json(input)

    expect(clause_titles(doc)).to include("Level 1", "Level 60")
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

    stale = File.join(out, "generic.json")
    File.write(stale, "{\"stale\":true}")

    log, status = run_compile(adoc, "generic")

    expect(log).not_to include("RAISED")
    expect(status.exitstatus).to eq(1)
    expect(log).to match(/POOLED: \[.*cannot serialize the generic document/)
    expect(Dir[File.join(out, "*.json")]).to be_empty
  end

  it "reports a SystemStackError from the model walk as a JSON output error" do
    errors = export_json_failing_with(SystemStackError.new("deep"))

    expect(errors).to eq(["the json output failed: SystemStackError: deep"])
  end

  it "names the flavor by the last short of a processor with aliases" do
    require "metanorma/mirror"
    compile = described_class.new
    compile.instance_variable_set(:@processor,
                                  instance_double(Metanorma::Processor,
                                                  short: %i[csd cc]))
    compile.instance_variable_set(:@errors, [])
    pipeline = instance_double(Metanorma::Mirror::Output::Pipeline,
                               process: Struct.new(:content).new(nil))
    allow(Metanorma::Mirror::Output::Pipeline).to receive(:new)
      .and_return(pipeline)

    compile.send(:export_json, "<metanorma/>", { out: File.join(out, "x.json") })

    expect(Metanorma::Mirror::Output::Pipeline)
      .to have_received(:new).with(hash_including(flavor: "cc"))
  end
end
