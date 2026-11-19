# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"

RSpec.describe Metanorma::Collection do
  # relaton 3.1.6+ takes serialized XML from Relaton::Cli.parse_xml, not a
  # Nokogiri element: the Moxml parse path calls `.read` on its argument and
  # lutaml-model wraps the NoMethodError as InvalidFormatError, breaking
  # every `Metanorma::Collection.parse` of a metanorma-collection XML with a
  # bibdata.
  describe "parsing a metanorma-collection XML with a bibdata" do
    let(:collection_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma-collection xmlns="http://metanorma.org">
          <bibdata type="collection">
            <title language="en" type="title-main">Probe Collection</title>
            <docidentifier type="iso" primary="true">ISO 12345</docidentifier>
          </bibdata>
          <entry index="true">
            <identifier>_</identifier>
            <type>collection</type>
            <title>Probe Collection</title>
          </entry>
        </metanorma-collection>
      XML
    end

    it "parses the bibdata into a Relaton object" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "collection.xml")
        File.write(path, collection_xml)
        collection = described_class.parse(path)
        bibdata = collection.bibdata
        expect(bibdata).to be_a(Relaton::Bib::ItemData)
        expect(bibdata.title.map(&:content)).to eq(["Probe Collection"])
      end
    end

    it "keeps the docidentifier type, content and primary flag" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "collection.xml")
        File.write(path, collection_xml)
        collection = described_class.parse(path)
        docid = collection.bibdata.docidentifier.first
        expect(docid.content).to eq("ISO 12345")
        expect(docid.type).to eq("iso")
        expect(docid.primary).to be(true)
      end
    end

    it "round-trips the docidentifier through the config XML" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "collection.xml")
        File.write(path, collection_xml)
        collection = described_class.parse(path)
        xml = collection.config.to_xml
        expect(xml)
          .to include(%q{<docidentifier type="iso" primary="true">} \
                      "ISO 12345</docidentifier>")
      end
    end
  end
end
