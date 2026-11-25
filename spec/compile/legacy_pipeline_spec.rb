# frozen_string_literal: true

require "metanorma"
require "tmpdir"
require "fileutils"

# Guard for the legacy converter bridge (metanorma-standoc#1387): while the
# Document-model pipeline lands, the default compile path must keep running
# the asciidoctor front-end and writing its structural XML.
RSpec.describe "Legacy compile path" do
  let(:fixture) do
    File.expand_path("fixtures/native-document/source.adoc", __dir__)
  end

  it "stays the default pipeline" do
    expect(Metanorma::Compile.new.compile_pipeline({})).to eq(:legacy)
  end

  it "compiles through asciidoctor and writes semantic and presentation XML" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source.adoc")
      FileUtils.cp(fixture, source)
      compiler = Metanorma::Compile.new
      expect(compiler).not_to receive(:compile_document)
      compiler.compile(
        source, type: :iso, extension_keys: %i[xml presentation], novalid: true
      )
      semantic = File.join(dir, "source.xml")
      presentation = File.join(dir, "source.presentation.xml")
      expect(File).to exist(semantic)
      expect(File).to exist(presentation)
      expect(File.read(semantic)).to include("<metanorma")
      expect(File.read(semantic)).to include('anchor="scope"')
    end
  end
end
