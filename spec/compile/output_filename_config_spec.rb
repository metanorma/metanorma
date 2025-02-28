# frozen_string_literal: true

RSpec.describe Metanorma::Compile::OutputFilenameConfig do
  describe "#generate_filename" do
    let(:relaton_data) do
      {

        "docidentifier" => "ISO/IEC FDIS 10118-3",
        "language" => "en",
        "edition" => "2",
        "doctype" => "international-standard",
        "docnumber" => "10118",
        "partnumber" => "3",
      }
    end

    let(:config) { Metanorma::Compile::OutputFilenameConfig.new(template) }

    subject(:filename) { config.generate_filename(relaton_data) }

    context "with an empty template" do
      let(:template) do
        ""
      end
      it { is_expected.to eq("iso-iec-fdis-10118-3") }
    end

    context "with a valid template" do
      let(:template) do
        "{{ document.docidentifier | downcase" \
        " | replace: '/' , '-'" \
        " | replace: ' ' , '-' }}"
      end
      it { is_expected.to eq("iso-iec-fdis-10118-3") }
    end

    context "with a template that has a missing variable" do
      let(:template) do
        "{{ nonexistent }}_{{ document.language }}"
      end
      it { is_expected.to eq("_en") }
    end

    context "with a template that has conditionals" do
      let(:template) do
        "{% if document.doctype == 'international-standard' %}" \
        "iso-"\
        "{% else %}"\
        "is-"\
        "{% endif %}" \
        "{{ document.docnumber }}-{{ document.partnumber }}"
      end
      it { is_expected.to eq("iso-10118-3") }
    end

    context "with an invalid template" do
      let(:template) do
        "{{ invalid syntax }"
      end

      it "raises Liquid::SyntaxError" do
        expect do
          config.generate_filename(relaton_data)
        end.to raise_error(Liquid::SyntaxError)
      end
    end
  end
end
