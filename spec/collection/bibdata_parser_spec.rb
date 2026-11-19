# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Metanorma::Collection::Config::BibdataParser do
  # The parser mirrors the flavor dispatch of relaton's Cli entry points
  # through relaton's library surface (Moxml parse, namespace stripping,
  # Registry processor dispatch); these specs pin that behavior.

  describe ".from_xml" do
    let(:namespaced_xml) do
      <<~XML
        <bibdata xmlns="http://metanorma.org" type="collection">
          <title language="en" type="title-main">Probe Collection</title>
          <docidentifier type="iso" primary="true">ISO 12345</docidentifier>
          <relation type="part-of">
            <bibitem>
              <title language="en" type="title-main">Probe Part</title>
              <docidentifier type="iso">ISO 2</docidentifier>
            </bibitem>
          </relation>
        </bibdata>
      XML
    end

    it "parses a namespaced bibdata with flavor dispatch" do
      bibdata = described_class.from_xml(namespaced_xml)
      expect(bibdata).to be_a(Relaton::Bib::ItemData)
      docid = bibdata.docidentifier.first
      expect(docid.content).to eq("ISO 12345")
      expect(docid.type).to eq("iso")
      expect(docid.primary).to be(true)
    end

    it "strips namespaces so a nested relation bibitem parses" do
      # lutaml-model skips prefixed elements and raises on a nested
      # relation/bibitem in a default namespace, so the parse only works
      # through the namespace-stripped copy
      bibdata = described_class.from_xml(namespaced_xml)
      expect(bibdata.relation).not_to be_empty
      expect(bibdata.relation.first.bibitem.title.first.content)
        .to eq("Probe Part")
    end

    it "falls back to the base Relaton item for an unknown flavor" do
      xml = <<~XML
        <bibdata type="collection">
          <docidentifier type="zzz">Z 1</docidentifier>
        </bibdata>
      XML
      bibdata = described_class.from_xml(xml)
      expect(bibdata).to be_a(Relaton::Bib::ItemData)
      expect(bibdata.docidentifier.first.content).to eq("Z 1")
    end

    it "returns nil for a non-XML source" do
      expect(described_class.from_xml("not xml at all")).to be_nil
    end

    it "returns nil for a nil source" do
      expect(described_class.from_xml(nil)).to be_nil
    end

    it "lets unexpected errors surface instead of degrading to nil" do
      # a non-string argument is a caller bug: the narrow Moxml::ParseError
      # rescue must not swallow it
      element = Nokogiri::XML("<bibdata/>").root
      expect { described_class.from_xml(element) }
        .to raise_error(NoMethodError)
    end
  end

  describe ".from_yaml" do
    it "dispatches on the ext flavor" do
      bibdata = described_class.from_yaml(
        { "docidentifier" => { "type" => "iso", "content" => "ISO 12345" },
          "ext" => { "flavor" => "iso" } },
      )
      expect(bibdata).to be_a(Relaton::Bib::ItemData)
      expect(bibdata.docidentifier.first.content).to eq("ISO 12345")
    end

    it "dispatches on the leading word of the docidentifier content" do
      bibdata = described_class.from_yaml(
        { "docidentifier" => { "content" => "ISO 17301-1:2016" } },
      )
      expect(bibdata).to be_a(Relaton::Bib::ItemData)
      expect(bibdata.docidentifier.first.content).to eq("ISO 17301-1:2016")
    end

    it "falls back to the base Relaton item without a dispatchable flavor" do
      bibdata = described_class.from_yaml(
        { "docidentifier" => { "content" => "Z 1" } },
      )
      expect(bibdata).to be_a(Relaton::Bib::ItemData)
      expect(bibdata.docidentifier.first.content).to eq("Z 1")
    end
  end
end
