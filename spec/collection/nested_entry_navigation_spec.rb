# frozen_string_literal: true

require "spec_helper"

# metanorma-cli#496: a document entry can carry nested entries of its own
# (publication > part > section). FileLookup already compiles them; the
# collection navigation used to drop everything below a document entry.
RSpec.describe Metanorma::Collection::Renderer do
  def manifest
    Metanorma::Collection::Config::Config.from_yaml(<<~YAML).manifest
      manifest:
        level: collection
        title: Publication
        docref:
          - file: part-a.xml
            identifier: S-4 Part A
          - file: part-b.xml
            identifier: S-4 Part B
            entry:
              - file: part-b-sec-1.xml
                identifier: S-4 B-100
              - file: part-b-sec-2.xml
                identifier: S-4 B-200
                entry:
                  - file: part-b-sec-2-1.xml
                    identifier: S-4 B-210
    YAML
  end

  let(:files) do
    double("files").tap do |f|
      allow(f).to receive(:get) { |ident, _| "#{ident.tr(' ', '_')}.xml" }
    end
  end

  let(:renderer) do
    described_class.allocate.tap do |r|
      isodoc = double("isodoc")
      allow(isodoc).to receive(:docid_prefix) { |_, ident| ident }
      r.instance_variable_set(:@c, HTMLEntities.new)
      r.instance_variable_set(:@isodoc, isodoc)
      r.instance_variable_set(:@files, files)
    end
  end

  def nav(html)
    Nokogiri::HTML.fragment(html)
  end

  def link_texts(node)
    node.xpath(".//a").map(&:text)
  end

  it "nests a document's entries under it in the index file" do
    doc = nav(renderer.indexfile(manifest))

    expect(link_texts(doc)).to eq(
      ["S-4 Part A", "S-4 Part B", "S-4 B-100", "S-4 B-200", "S-4 B-210"],
    )
    part_b = doc.at(".//li[a[text()='S-4 Part B']]")
    expect(link_texts(part_b.at("./ul"))).to eq(
      ["S-4 B-100", "S-4 B-200", "S-4 B-210"],
    )
    sec2 = part_b.at(".//li[a[text()='S-4 B-200']]")
    expect(link_texts(sec2.at("./ul"))).to eq(["S-4 B-210"])
    expect(doc.at(".//li[a[text()='S-4 Part A']]/ul")).to be_nil
  end

  it "links nested entries to their own output files" do
    doc = nav(renderer.indexfile(manifest))

    expect(doc.at(".//a[text()='S-4 B-210']")["href"])
      .to eq("S-4_B-210.html")
  end

  it "leaves out nested entries flagged index: false" do
    m = manifest
    m.entry[1].entry[0].index = false

    expect(link_texts(nav(renderer.indexfile(m))))
      .not_to include("S-4 B-100")
  end

  it "nests a document's entries in the Liquid navigation object" do
    docrefs = nav(renderer.index_object(manifest)[:docrefs])

    part_b = docrefs.at(".//li[a[text()='S-4 Part B']]")
    expect(link_texts(part_b.at("./ul"))).to eq(
      ["S-4 B-100", "S-4 B-200", "S-4 B-210"],
    )
  end

  it "lists nested entries after their parent in the Liquid docrefs" do
    idents = renderer.liquid_docrefs(manifest.entry).map { |d| d["identifier"] }

    expect(idents).to eq(
      ["S-4 Part A", "S-4 Part B", "S-4 B-100", "S-4 B-200", "S-4 B-210"],
    )
  end
end
