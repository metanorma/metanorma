require_relative "../spec_helper"
require "digest"

# real isodoc converter + real manifest; the parent is structural data
FileLookupParent = Struct.new(:xml, :isodoc, :isodoc_presxml, :compile,
                              :documents, :manifest, :format, keyword_init: true)

RSpec.describe Metanorma::Collection::FileLookup do
  let(:xml) do
    Nokogiri::XML(<<~XML)
      <iso-standard xmlns="http://riboseinc.com/isoxml">
      <sections>
      <clause id="c1" displayorder="1"><title>Clause 1</title>
      <note id="n1"><p>Note one.</p></note>
      </clause>
      </sections>
      </iso-standard>
    XML
  end

  let(:parent) do
    conv = IsoDoc::PresentationXMLConvert.new(language: "en", script: "Latn")
    conv.i18n_init("en", "Latn", nil)
    FileLookupParent.new(xml: xml, isodoc: conv, isodoc_presxml: conv,
                         compile: nil, documents: {},
                         manifest: Metanorma::Collection::Config::Manifest.new,
                         format: %w[xml presentation html])
  end

  def file_lookup
    described_class.new(".", parent)
  end

  # anchors without an unambiguous locality label were registered under
  # random UUIDs; they now carry SHA-256 placeholders keyed by the anchor
  # id, so the registry is deterministic per document
  it "registers label-less anchors under deterministic placeholders" do
    ret1 = {}
    ret2 = {}
    file_lookup.read_anchors1("n1", { type: nil, label: nil }, ret1)
    file_lookup.read_anchors1("n1", { type: nil, label: nil }, ret2)
    expected = Digest::SHA256
      .hexdigest("metanorma-anchor-placeholder/n1")

    expect(ret1["clause"][expected]).to eq("n1")
    expect(ret1).to eq(ret2)
    expect(ret1["clause"].keys)
      .not_to include(match(/[0-9a-f]{8}-[0-9a-f]{4}-/))
  end

  it "keeps labeled anchors keyed by their label" do
    ret = file_lookup.read_anchors(xml)

    expect(ret["clause"].keys).to include("1")
    expect(ret["clause"].values).to include("c1")
  end

  it "builds a deterministic anchor registry from a document" do
    first = file_lookup.read_anchors(xml)
    second = file_lookup.read_anchors(xml)

    expect(first).to eq(second)
  end
end
