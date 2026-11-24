# frozen_string_literal: true

if ENV['METANORMA_DOCUMENT_PIPELINE_TEST'] == '1'
  require "metanorma"
  require "tmpdir"

  RSpec.describe "Native ISO compile validation" do
    let(:source) { File.join(__dir__, "fixtures/native-document/source.adoc") }

    it "runs the real shared ISO grammar and native registry before presentation" do
      Dir.mktmpdir do |dir|
        result = Metanorma::Compile.new.compile(source, pipeline: :document,
          type: :iso, output_dir: dir, extension_keys: [:html])
        expect(result.validation.report).to be_a(Metanorma::Iso::Validation::Report)
        expect(result.validation.schema_errors).to be_empty
        expect(result.validation.report.issues.map(&:code)).to include("ISO_31")
        expect(result.validation.report.issues.map(&:code)).not_to include("ISO_29", "ISO_56")
        expect(result.validation.fatal_messages).to be_empty
        schema = Object.new.extend(Metanorma::Standoc::Validate::Schema)
        expect(schema.shared_schema_errors(result.presentation_model.to_xml,
          flavor: "iso", representation: "presentation")).to be_empty
        expect(File.read(result.outputs.fetch(:html))).to include("Retained body.", "Clause 2", "First item", "Second item", "<table")
        expect(Dir.glob(File.join(dir, "*.xml"))).to be_empty
      end
    end

    it "reports missing source metadata without inventing required values" do
      Dir.mktmpdir do |dir|
        input = File.join(dir, "bare.adoc")
        File.write(input, "= Bare title\n\n== Scope\n\nBody.\n")
        result = Metanorma::Compile.new.compile(input, pipeline: :document,
          type: :iso, extension_keys: [:html])
        expect(result.validation.schema_errors).not_to be_empty
        expect(result.validation).not_to be_valid
        expect(Array(result.semantic_model.bibdata.doc_identifier)).to be_empty
      end
    end

    it "stops before rendering on strict findings from an actual broken reference" do
      Dir.mktmpdir do |dir|
        input = File.join(dir, "broken.adoc")
        File.write(input, File.read(source).sub('<<method>>', '<<missing>>'))
        expect do
          Metanorma::Compile.new.compile(input, pipeline: :document, type: :iso,
            document_validation_profile: :strict, extension_keys: [:html])
        end.to raise_error(Metanorma::Compile::DocumentPipeline::ValidationError) { |error|
          expect(error.validation.report.issues.map(&:code)).to include("ISO_56")
          expect(error.validation.fatal_messages).not_to be_empty
        }
        expect(Dir.glob(File.join(dir, "*.html")).reject { |f| f.end_with?(".err.html") }).to be_empty
        expect(Dir.glob(File.join(dir, "*.xml"))).to be_empty
      end
    end

    it "validates both real source frontends with the same semantic output" do
      Dir.mktmpdir do |dir|
        compiler = Metanorma::Compile.new
        first = compiler.compile(source, pipeline: :document, type: :iso,
          output_dir: File.join(dir, "adoc"), extension_keys: [:html])
        second = compiler.compile(source.sub('.adoc', '.md'), pipeline: :document,
          type: :iso, output_dir: File.join(dir, "markdown"), extension_keys: [:html])
        expect(second.semantic_model.to_xml).to eq(first.semantic_model.to_xml)
        expect(second.validation.schema_errors).to eq(first.validation.schema_errors)
        expect(second.validation.report.issues.map(&:code)).to eq(first.validation.report.issues.map(&:code))
      end
    end
  end
end
