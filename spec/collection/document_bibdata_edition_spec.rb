# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"

RSpec.describe Metanorma::Collection do
  describe "parsing a document with a localized edition" do
    it "keeps the language-neutral edition in the bibdata" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "document.xml"), <<~XML)
          <?xml version="1.0" encoding="UTF-8"?>
          <metanorma xmlns="https://www.metanorma.org/ns/standoc" type="standard" flavor="iso">
            <bibdata type="standard">
              <title language="en" type="main">Dummy</title>
              <docidentifier type="ISO" primary="true">ISO 1:2026</docidentifier>
              <edition language="">1</edition>
              <edition language="en">first edition</edition>
              <language current="true">en</language>
              <script current="true">Latn</script>
              <status>
                <stage abbreviation="IS">60</stage>
                <substage>60</substage>
              </status>
              <copyright>
                <from>2026</from>
                <owner>
                  <organization><name>ISO</name></organization>
                </owner>
              </copyright>
              <ext>
                <doctype>international-standard</doctype>
              </ext>
            </bibdata>
          </metanorma>
        XML
        File.write(File.join(dir, "collection.yml"), <<~YAML)
          directives:
            - documents-external
          bibdata:
            title:
              type: title-main
              language: en
              content: Dummy Collection
            type: collection
            docid:
              type: iso
              id: ISO 12345
            edition:
              content: 1
          manifest:
            level: collection
            title: Dummy Collection
            manifest:
              - level: subcollection
                title: Standards
                docref:
                  - fileref: document.xml
                    identifier: ISO 1:2026
        YAML
        mc = Metanorma::Collection.parse(File.join(dir, "collection.yml"))
        docs = mc.documents.values
        expect(docs).not_to be_empty
        expect(docs.first.bibitem.edition.content.to_s).to eq("1")
      end
    end
  end
end
