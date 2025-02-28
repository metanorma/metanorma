# frozen_string_literal: true

RSpec.describe Metanorma::Compile::OutputFilename do
  let(:filename_noext) { "test" }
  let(:output_dir) { "output" }
  let(:processor) do
    double("processor", output_formats: { html: "html", pdf: "pdf" })
  end

  subject(:output_filename) do
    described_class.new(filename_noext, output_dir, processor)
  end

  describe "#semantic_xml" do
    it "returns full path with .xml extension" do
      expect(output_filename.semantic_xml).to eq(File.expand_path("output/test.xml"))
    end
  end

  describe "#presentation_xml" do
    it "returns full path with .presentation.xml extension" do
      expect(output_filename.presentation_xml).to eq(File.expand_path("output/test.presentation.xml"))
    end
  end

  describe "#for_format" do
    context "when format exists" do
      it "returns full path with format extension" do
        expect(output_filename.for_format(:html)).to eq(File.expand_path("output/test.html"))
      end
    end

    context "when format does not exist" do
      it "returns nil" do
        expect(output_filename.for_format(:unknown)).to be_nil
      end
    end
  end

  context "without output_dir" do
    subject(:output_filename) do
      described_class.new(filename_noext, nil, processor)
    end

    it "uses source directory" do
      expect(output_filename.semantic_xml).to eq(File.expand_path("test.xml"))
    end
  end
end
