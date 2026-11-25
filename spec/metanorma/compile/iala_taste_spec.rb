require "spec_helper"
require "metanorma-iho"

# IALA is a taste-only flavor (metanorma-taste data/iala, base flavor iho; no
# metanorma-iala gem). Core must resolve it to iho, carry its PDF taste
# attributes into the PDF converter options, and offer the pdf output the taste
# declares (metanorma/metanorma#699, #686).
RSpec.describe "IALA taste-only flavor" do
  let(:pdf_attrs) { { fonts: "Carlito;Source Code Pro", toclevels: "3" } }

  it "is registered as a taste of iho" do
    expect(Metanorma::TasteRegister.instance.aliases[:iala]).to eq :iho
  end

  it "resolves to iho in the compile driver" do
    compile = Metanorma::Compile.allocate
    expect(compile.taste2flavor(:iala).to_sym).to eq :iho
    expect(compile.taste2flavor("iala").to_sym).to eq :iho
  end

  it "resolves to iho in collection utilities" do
    expect(Metanorma::Collection::Util.taste2flavor(:iala).to_sym).to eq :iho
  end

  it "declares pdf among the taste's output extensions" do
    exts = Metanorma::TasteRegister.get_config(:iala)
      .base_override.value_attributes.output_extensions.split(",").map(&:strip)
    expect(exts).to include("pdf")
  end

  it "offers pdf among the effective output formats" do
    processor = Class.new do
      def output_formats = { xml: "xml", html: "html", pdf: "pdf" }
    end.new
    compile = Metanorma::Compile.allocate
      .tap { |c| c.instance_variable_set(:@processor, processor) }
    expect(compile.send(:effective_output_formats, supplied_type: :iala))
      .to include(pdf: "pdf")
  end

  context "with a collection renderer on the iala taste" do
    let(:renderer) do
      Metanorma::Collection::Renderer.allocate.tap do |r|
        r.instance_variable_set(:@flavor, :iala)
        r.instance_variable_set(:@compile_options, {})
      end
    end

    it "prepares the iho backend with the taste's pdf attributes" do
      allow(Metanorma::Collection::Util).to receive(:taste2isodoc_attrs)
        .with(:iala, :pdf).and_return(pdf_attrs)
      flavor, taste_opts, = renderer.send(:pdfconv_prep)
      expect(flavor).to eq :iho
      expect(taste_opts).to eq pdf_attrs
    end

    it "passes the taste's pdf attributes into the pdf converter options" do
      allow(Metanorma::Collection::Util).to receive(:taste2isodoc_attrs)
        .with(:iala, :pdf).and_return(pdf_attrs)
      converter = double("converter")
      backend = double("backend", converter: converter)
      allow(Asciidoctor).to receive(:load).and_return(backend)
      captured = nil
      allow(Metanorma::Collection::Renderer::PdfOptionsNode)
        .to receive(:new) { |flavor, opts| captured = [flavor, opts] }
      allow(converter).to receive(:pdf_converter)

      renderer.send(:pdfconv, {})

      expect(captured.first).to eq :iho
      expect(captured.last).to include(toclevels: "3")
      expect(captured.last[:fonts]).to eq "Carlito;Source Code Pro"
    end
  end
end
