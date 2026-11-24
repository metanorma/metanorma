# frozen_string_literal: true

require "metanorma"
require "tmpdir"

RSpec.describe Metanorma::Compile::DocumentPipeline do
  subject(:pipeline) { described_class.new }

  describe "#native_presenter" do
    it "returns nil for a flavor that ships no presentation transformer" do
      allow(Metanorma::Core::FlavorLoader).to receive(:taste2flavor).and_return(:nosuchflavor)
      expect(pipeline.send(:native_presenter, :nosuchflavor)).to be_nil
    end

    it "does not swallow a missing dependency of an existing transformer" do
      allow(Metanorma::Core::FlavorLoader).to receive(:taste2flavor).and_return(:other)
      allow(pipeline).to receive(:require).with("metanorma/other/presentation/transformer")
        .and_raise(LoadError.new("cannot load such file -- dep").tap { |e|
                     allow(e).to receive(:path).and_return("dep")
                   })
      expect do
        pipeline.send(:native_presenter, :other)
      end.to raise_error(LoadError)
    end
  end

  describe "in_memory output" do
    it "returns contents and writes no file when in_memory is set" do
      root = Class.new do
        def type = "presentation"
        def to_xml = "<x/>"
      end
      model = root.new
      allow(pipeline).to receive_messages(model_root: root, source_model: model,
                                          render_html: "<html/>")
      Dir.mktmpdir do |dir|
        result = pipeline.compile(File.join(dir, "a.adoc"),
                                  type: :demo, novalid: true, in_memory: true,
                                  output_dir: dir, extension_keys: %i[html xml],
                                  document_presenter: ->(m, **) { m })
        expect(result.outputs).to eq({})
        expect(result.contents).to eq(html: "<html/>", xml: "<x/>")
        expect(Dir.children(dir)).to be_empty
      end
    end
  end
end
