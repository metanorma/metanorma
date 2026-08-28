require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "mko output format" do
  it "exports an MKO bundle via the compile pipeline" do
    skip "metanorma-document not in the bundle" unless begin
      require "metanorma/document"
      true
    rescue LoadError
      false
    end

    out = Dir.mktmpdir("mko-compile")
    script = <<~RUBY
      require "metanorma"
      c = Metanorma::Compile.new
      c.compile(ARGV[0], type: "iso", extension_keys: [:mko],
                output_dir: ARGV[1], no_install_fonts: true)
      exit(c.errors.empty? ? 0 : 1)
    RUBY
    # A subprocess keeps the flavor-gem load (and its asciidoctor
    # extension registration) single-shot: under rspec the in-process
    # registry has already registered extensions and the second
    # registration is frozen by asciidoctor.
    ok, status = Open3.capture2e(RbConfig.ruby, "-e", script,
                                 "spec/fixtures/mko/iso-semantic.xml", out)
    begin
      expect(status.success?).to be(true), ok

      # mko is a presentation-based format: the presentation XML is
      # generated before the bundle.
      expect(Dir[File.join(out, "*.presentation.xml")]).not_to be_empty

      bundles = Dir[File.join(out, "*.mko")].select { |p| File.directory?(p) }
      expect(bundles.size).to eq(1)
      manifest = JSON.parse(File.read(File.join(bundles.first, "manifest.json")))
      expect(manifest["schema"]).to eq("metanorma-mko")
      names = manifest["components"].map { |c| c["name"] }
      expect(names).to include("document", "bibdata", "identifiers",
                               "glossary", "units", "edges")
      units = manifest["components"].find { |c| c["name"] == "units" }
      expect(units["count"]).to be > 100
    ensure
      FileUtils.remove_entry(out)
    end
  end
end
