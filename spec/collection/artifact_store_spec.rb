# frozen_string_literal: true

require_relative "../spec_helper"
require "tmpdir"
require "metanorma/collection/artifact_store"

RSpec.describe Metanorma::Collection::ArtifactStore do
  around do |example|
    Dir.mktmpdir do |d|
      @dir = File.join(d, Metanorma::Collection::ArtifactStore::DEFAULT_DIRNAME)
      example.run
    end
  end

  let(:store) { described_class.new(@dir) }
  let(:hash) { described_class.content_hash("source-bytes", "metanorma-1.2.3") }

  it "names an artefact <docid-slug>.<hash>.<stage>.<format>" do
    expect(File.basename(store.path("ISO 10303-11", hash, :anchors)))
      .to eq "ISO-10303-11.#{hash}.anchors.json"
    expect(store.path("x", hash, :semantic)).to end_with ".semantic.xml"
  end

  it "is absent before write and present after (the resumption predicate)" do
    expect(store.key?("ISO 10303-11", hash, :anchors)).to be false
    store.write("ISO 10303-11", hash, :anchors, %({"a":1}))
    expect(store.key?("ISO 10303-11", hash, :anchors)).to be true
    expect(store.read("ISO 10303-11", hash, :anchors)).to eq %({"a":1})
  end

  it "writes idempotently: a re-run overwrites with identical bytes" do
    first = store.write("d", hash, :semantic, "<xml/>")
    again = store.write("d", hash, :semantic, "<xml/>")
    expect(again).to eq first
    expect(store.read("d", hash, :semantic)).to eq "<xml/>"
  end

  it "rejects an unknown stage -- the vocabulary is closed" do
    expect { store.path("x", hash, :bogus) }.to raise_error(KeyError)
  end

  describe ".content_hash" do
    it "is deterministic over the same inputs" do
      expect(described_class.content_hash("a", "b"))
        .to eq described_class.content_hash("a", "b")
    end

    it "does not collide across different input boundaries" do
      expect(described_class.content_hash("a", "b"))
        .not_to eq described_class.content_hash("ab", "")
    end
  end
end

RSpec.describe Metanorma::Collection::NullArtifactStore do
  subject(:null) { described_class.new }

  it "is inert: never reports a hit, never writes, no path" do
    expect(null.key?("x", "h", :semantic)).to be false
    expect(null.read("x", "h", :semantic)).to be_nil
    expect(null.write("x", "h", :semantic, "y")).to be_nil
    expect(null.path("x", "h", :semantic)).to be_nil
  end
end
