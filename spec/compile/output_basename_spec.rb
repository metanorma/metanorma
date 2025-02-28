# frozen_string_literal: true

RSpec.describe Metanorma::Compile::OutputBasename do
  let(:filename_noext) { "test" }
  let(:output_dir) { "output" }
  let(:processor) do
    double("processor", output_formats: { html: "html", pdf: "pdf" })
  end

  subject(:output_basename) do
    described_class.new(filename_noext, output_dir, processor)
  end

  describe "#semantic_xml" do
    it "returns basename with .xml extension" do
      expect(output_basename.semantic_xml).to eq("output/test.xml")
    end
  end

  describe "#presentation_xml" do
    it "returns basename with .presentation.xml extension" do
      expect(output_basename.presentation_xml).to eq("output/test.presentation.xml")
    end
  end

  describe "#for_format" do
    context "when format exists" do
      it "returns basename with format extension" do
        expect(output_basename.for_format(:html)).to eq("output/test.html")
      end
    end

    context "when format does not exist" do
      it "returns nil" do
        expect(output_basename.for_format(:unknown)).to be_nil
      end
    end
  end

  context "without output_dir" do
    subject(:output_basename) do
      described_class.new(filename_noext, nil, processor)
    end

    it "uses source directory" do
      expect(output_basename.semantic_xml).to eq("test.xml")
    end
  end
end
