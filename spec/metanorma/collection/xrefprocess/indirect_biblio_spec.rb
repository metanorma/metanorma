# frozen_string_literal: true

require "nokogiri"
require "metanorma/collection/xrefprocess/xrefprocess"

RSpec.describe Metanorma::Collection::XrefProcess do
  describe ".insert_indirect_biblio" do
    it "drops the anchor on hidden copies of internal bibitems" do
      xml = Nokogiri::XML(<<~XML)
        <metanorma xmlns="https://www.metanorma.org/ns/standard">
          <bibliography>
            <references normative="true">
              <bibitem id="ref8601" anchor="ISO 8601" type="standard">
                <docidentifier>ISO 8601</docidentifier>
              </bibitem>
            </references>
          </bibliography>
        </metanorma>
      XML
      hidden = xml.at("//xmlns:bibliography")
                  .add_child("<references hidden='true'/>")

      described_class.insert_indirect_biblio(hidden, ["summ_ref8601"],
                                             "summ", xml)
      copy = hidden.at("//xmlns:bibitem[@id='summ_ref8601']")

      aggregate_failures do
        expect(copy).not_to be_nil
        expect(copy["anchor"]).to be_nil
        expect(copy["id"]).to eq("summ_ref8601")
        expect(xml.at("//xmlns:bibitem[@id='ref8601']")["anchor"]).to eq("ISO 8601")
      end
    end

    it "creates plain indirect entries when no internal bibitem matches" do
      xml = Nokogiri::XML(<<~XML)
        <metanorma xmlns="https://www.metanorma.org/ns/standard">
          <bibliography/>
        </metanorma>
      XML
      hidden = xml.at("//xmlns:bibliography")
                  .add_child("<references hidden='true'/>")

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
