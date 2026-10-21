# frozen_string_literal: true

require "nokogiri"
require "metanorma/collection/xrefprocess/xrefprocess"

IsoNsStub = Struct.new(:dummy) do
  def ns(xpath)
    Metanorma::Utils.ns(xpath)
  end
end

RSpec.describe Metanorma::Collection::XrefProcess do
  describe ".insert_indirect_biblio" do
    def document_with_bibliography(bibliography)
      Nokogiri::XML(<<~XML)
        <metanorma xmlns="https://www.metanorma.org/ns/standard">
          #{bibliography}
        </metanorma>
      XML
    end

    def hidden_references(xml)
      bibliography = xml.at("//xmlns:bibliography")
      references = Nokogiri::XML::Node.new("references", xml.document)
      references["hidden"] = "true"
      bibliography.add_child(references)
      references
    end

    it "drops the anchor on hidden copies of internal bibitems" do
      xml = document_with_bibliography(<<~XML)
        <bibliography>
          <references normative="true">
            <bibitem id="bib8601" anchor="ref8601" type="internal">
              <docidentifier type="repository">iso-10303/ref8601</docidentifier>
            </bibitem>
          </references>
        </bibliography>
      XML
      hidden = hidden_references(xml)
      described_class.xref_preprocess(xml, IsoNsStub.new)

      described_class.insert_indirect_biblio(hidden, ["summ_ref8601"],
                                             "summ", xml)
      copy = hidden.at("//xmlns:bibitem[@id='summ_ref8601']")

      aggregate_failures do
        expect(copy).not_to be_nil
        expect(copy["anchor"]).to be_nil
        expect(copy["id"]).to eq("summ_ref8601")
        expect(xml.at("//xmlns:bibitem[@id='bib8601']")["anchor"])
          .to eq("ref8601")
      end
    end

    it "creates plain indirect entries when no internal bibitem matches" do
      xml = document_with_bibliography("<bibliography/>")
      hidden = hidden_references(xml)
      described_class.xref_preprocess(xml, IsoNsStub.new)

      described_class.insert_indirect_biblio(hidden, ["summ_ext"], "summ", xml)
      entry = hidden.at("//xmlns:bibitem[@id='summ_ext']")

      aggregate_failures do
        expect(entry).not_to be_nil
        expect(entry["anchor"]).to eq("summ_ext")
        expect(entry["type"]).to eq("internal")
      end
    end
  end
end
