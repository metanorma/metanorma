# frozen_string_literal: true

if ENV['METANORMA_DOCUMENT_PIPELINE_TEST'] == '1'
  require "metanorma"
  require "tmpdir"

  RSpec.describe Metanorma::Compile::DocumentPipeline do
    let(:compiler) { Metanorma::Compile.new }

    it "keeps legacy as the default and rejects unknown pipeline selections" do
      expect(compiler.compile_pipeline({})).to eq(:legacy)
      expect(compiler.compile_pipeline(pipeline: "document")).to eq(:document)
      expect { compiler.compile_pipeline(pipeline: :unknown) }
        .to raise_error(ArgumentError, /Unknown compile pipeline/)
    end

    it "routes the normal compiler entrypoint to native source validation" do
      expect { compiler.compile("input.adoc", pipeline: :document, novalid: true) }
        .to raise_error(ArgumentError, /explicit type/)
      expect { compiler.compile("input.adoc", pipeline: :document, type: :iso,
                                            format: :unknown, novalid: true) }
        .to raise_error(ArgumentError, /source format/)
    end

    it "rejects unsupported outputs and legacy-only features before reading a source" do
      expect { described_class.new.compile("input.adoc", type: :iso,
                                                         extension_keys: [:pdf]) }
        .to raise_error(ArgumentError, /output formats.*pdf/)
      expect { described_class.new.compile("input.adoc", type: :iso,
                                                         sectionsplit: true) }
        .to raise_error(ArgumentError, /sectionsplit/)
    end

    it "runs real source through the native ISO presenter, shared LADL and registered renderer" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "document.adoc")
        File.write(source, "= Example\n:language: en\n\n[[scope]]\n== Scope\n\nSee <<method>> and *rich body*.\n\n[[method]]\n== Method\n\nRetained body.\n")
        allow(compiler).to receive(:generate_semantic_xml).and_call_original
        result = compiler.compile(source, pipeline: :document, type: :iso,
                                          extension_keys: [:html], novalid: true)
        expect(result.semantic_model).to be_a(Metanorma::Iso::Document::Root)
        expect(result.semantic_model.type).to eq("semantic")
        expect(result.presentation_model.type).to eq("presentation")
        html = File.read(result.outputs.fetch(:html))
        expect(html).to include("Retained body.", "rich body", "Clause 2")
        expect(compiler).not_to have_received(:generate_semantic_xml)
        expect(Dir.glob(File.join(dir, "*.xml"))).to be_empty
      end
    end

    it "requires an actual native presenter rather than an identity fallback" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "document.md")
        File.write(source, "# Example\n\nA real Markdown paragraph.\n")
        expect do
          compiler.compile(source, pipeline: :document, type: :standoc,
                                   extension_keys: [:html], novalid: true)
        end.to raise_error(described_class::UnavailableStageError,
                           /standoc has no native presentation transform/)
        expect(Dir.glob(File.join(dir, "*.xml"))).to be_empty
      end
    end

    it "writes semantic and presentation XML only as explicitly requested interchange" do
      Dir.mktmpdir do |dir|
        source = File.join(dir, "document.adoc")
        File.write(source, "= Example\n:language: en\n\n== Scope\n\nBody.\n")
        result = compiler.compile(source, pipeline: :document, type: :iso,
                                          extension_keys: %i[html xml presentation], novalid: true)
        expect(result.outputs.keys).to eq(%i[html xml presentation])
        semantic = Metanorma::Iso::Document::Root.from_xml(File.read(result.outputs.fetch(:xml)))
        presentation = Metanorma::Iso::Document::Root.from_xml(File.read(result.outputs.fetch(:presentation)))
        expect(semantic.type).to eq("semantic")
        expect(presentation.type).to eq("presentation")
        expect(File.read(result.outputs.fetch(:presentation))).to include("fmt-ladl-label-data")
      end
    end

    it "compiles Markdown through the same actual ISO model and presentation contract" do
      Dir.mktmpdir do |dir|
        adoc = File.join(dir, "adoc.adoc")
        markdown = File.join(dir, "markdown.md")
        File.write(adoc, "= Example\n:language: en\n\n== Scope\n\nRetained *body*.\n")
        File.write(markdown, "---\nlanguage: en\n---\n\n# Example\n\n## Scope\n\nRetained **body**.\n")
        options = { pipeline: :document, type: :iso, extension_keys: [:html], novalid: true }
        first = compiler.compile(adoc, options.dup)
        second = compiler.compile(markdown, options.dup)
        expect(second.semantic_model.to_xml).to eq(first.semantic_model.to_xml)
        expect(second.presentation_model.to_xml).to eq(first.presentation_model.to_xml)
        expect(File.read(second.outputs.fetch(:html))).to include("<strong>body</strong>")
        expect(Dir.glob(File.join(dir, "*.xml"))).to be_empty
      end
    end
  end
else
  RSpec.describe "Optional native document compile" do
    it "runs under the pinned native compile feature bundle" do
      skip "Set METANORMA_DOCUMENT_PIPELINE_TEST=1 to select the native stack"
    end
  end
end
