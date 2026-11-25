require "spec_helper"
require "metanorma-iho"

# IALA is a taste-only flavor (metanorma-taste data/iala, base flavor iho; no
# metanorma-iala gem). Core must resolve it to iho, carry its PDF taste
# attributes into the PDF converter options, and offer the pdf output the taste
# declares (metanorma/metanorma#699, #686).
RSpec.describe Metanorma::Compile do # rubocop:disable RSpec/SpecFilePathFormat
  let(:pdf_attrs) { { fonts: "Carlito;Source Code Pro", toclevels: "3" } }

  it "is registered as a taste of iho" do
    expect(Metanorma::TasteRegister.instance.aliases[:iala]).to eq :iho
  end

  it "resolves a symbol to iho in the compile driver" do
    expect(described_class.allocate.taste2flavor(:iala).to_sym).to eq :iho
  end

  it "resolves a string to iho in the compile driver" do
    expect(described_class.allocate.taste2flavor("iala").to_sym).to eq :iho
  end

  it "resolves to iho in collection utilities" do
    expect(Metanorma::Collection::Util.taste2flavor(:iala).to_sym).to eq :iho
  end

  it "declares pdf among the taste's output extensions" do
    exts = Metanorma::TasteRegister.get_config(:iala)
      .base_override.value_attributes.output_extensions.split(",").map(&:strip)
    expect(exts).to include("pdf")
  end

  describe "effective output formats" do
    let(:processor) do
      Class.new do
        def output_formats = { xml: "xml", html: "html", pdf: "pdf" }
      end.new
    end
    let(:compile) do
      described_class.allocate
        .tap { |c| c.instance_variable_set(:@processor, processor) }
    end

    it "offers pdf" do
      expect(compile.send(:effective_output_formats, supplied_type: :iala))
        .to include(pdf: "pdf")
    end
  end

  context "with a collection renderer on the iala taste" do
    let(:renderer) do
      Metanorma::Collection::Renderer.allocate.tap do |r|
        r.instance_variable_set(:@flavor, :iala)
        r.instance_variable_set(:@compile_options, {})
      end
    end

    before do
      allow(Metanorma::Collection::Util).to receive(:taste2isodoc_attrs)
        .with(:iala, :pdf).and_return(pdf_attrs)
    end

    describe "backend preparation" do
      subject(:prep) { renderer.send(:pdfconv_prep) }

      it "uses the iho flavor" do
        expect(prep.first).to eq :iho
      end

      it "carries the taste's pdf attributes" do
        expect(prep[1]).to eq pdf_attrs
      end
    end

    describe "pdf converter options" do
      let(:captured) { [] }
      let(:converter) { Class.new { def pdf_converter(*); end }.new }
      let(:backend) { Struct.new(:converter).new(converter) }

      before do
        allow(Asciidoctor).to receive(:load).and_return(backend)
        allow(Metanorma::Collection::Renderer::PdfOptionsNode)
          .to receive(:new) { |flavor, opts| captured.replace([flavor, opts]) }
        renderer.send(:pdfconv, {})
      end

      it "uses the iho flavor" do
        expect(captured.first).to eq :iho
      end

      it "includes the taste's toclevels" do
        expect(captured.last).to include(toclevels: "3")
      end

      it "includes the taste's fonts" do
        expect(captured.last[:fonts]).to eq "Carlito;Source Code Pro"
      end
    end
  end
end
