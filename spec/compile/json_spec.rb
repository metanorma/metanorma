require "spec_helper"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "json output format" do
  def clauses(node)
    return [] unless node.is_a?(Hash)

    own = node["type"] == "clause" ? [node] : []
    own + Array(node["content"]).flat_map { |child| clauses(child) }
  end

  it "serializes the document model as Metanorma JSON" do
    skip "metanorma-document not in the bundle" unless begin
      require "metanorma/document"
      true
    rescue LoadError
      false
    end

    out = Dir.mktmpdir("json-compile")
    script = <<~RUBY
      require "metanorma"
      c = Metanorma::Compile.new
      c.compile(ARGV[0], type: "iso", extension_keys: [:json],
                output_dir: ARGV[1], no_install_fonts: true)
      exit(c.errors.empty? ? 0 : 1)
    RUBY
    # A subprocess keeps the flavor-gem load single-shot (see mko_spec).
    ok, status = Open3.capture2e(RbConfig.ruby, "-e", script,
                                 "spec/fixtures/mko/iso-semantic.xml", out)
    begin
      expect(status.success?).to be(true), ok

      files = Dir[File.join(out, "*.json")]
      expect(files.size).to eq(1)
      doc = JSON.parse(File.read(files.first))

      expect(doc["type"]).to eq("doc")
      expect(doc["attrs"]).to include("flavor" => "iso", "type" => "semantic")
      titles = clauses(doc).map { |c| c.dig("attrs", "title") }
      expect(titles).to include("Scope")
    ensure
      FileUtils.remove_entry(out)
    end
  end

  it "registers json beside mko as an opt-in harness format" do
    formats = Metanorma::Compile::HARNESS_OUTPUT_FORMATS
    expect(formats).to include(json: "json", mko: "mko")
  end
end
