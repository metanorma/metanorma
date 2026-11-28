# frozen_string_literal: true

require "spec_helper"
require "yaml"

# A manifest entry that declares neither an identifier nor a file used
# to keep the random-UUID attribute default (the "no id supplied"
# sentinel) as its identifier when nothing anchored a real id, making
# collection output carry a different value on every run. The sentinel
# is now replaced by a SHA-256 over the manifest's own content at the
# manifest_identifier seam (byte-determinism, isodoc#920 acceptance
# class).
RSpec.describe Metanorma::Collection::Manifest do
  def wrap(entries_yaml)
    config = Metanorma::Collection::Config::Config
      .from_yaml("manifest:\n#{entries_yaml.gsub(/^/, '  ')}").manifest
    collection = Metanorma::Collection.allocate
    described_class.new(config, collection, ".")
  end

  def entries_yaml
    <<~YAML
      entry:
        - title: Detached note
          type: precondition
        - title: Another note
          type: precondition
    YAML
  end

  it "derives the same identifier for identical content across runs" do
    first = wrap(entries_yaml).config.identifier
    second = wrap(entries_yaml).config.identifier

    # UUID-shaped (the sentinel contract), but stable across runs —
    # the pre-fix default minted a fresh random UUID per instance.
    expect(first).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    expect(first).to eq(second)
    expect(first).to eq(wrap(entries_yaml).config.identifier)
  end

  it "derives different identifiers for different content" do
    other = wrap(<<~YAML).config.identifier
      entry:
        - title: Detached note
          type: precondition
        - title: Different note
          type: precondition
    YAML

    expect(other).not_to eq(wrap(entries_yaml).config.identifier)
  end

  it "leaves a supplied identifier untouched and deterministically ids the parent" do
    manifest = wrap(<<~YAML)
      entry:
        - title: Detached note
          type: precondition
          identifier: ISO 1
    YAML

    expect(manifest.config.entry.first.identifier).to eq("ISO 1")
    # The parent declares no id: the sentinel is replaced by the
    # deterministic UUID-v5-shaped digest of the subtree content.
    expect(manifest.config.identifier)
      .to eq(wrap(<<~YAML).config.identifier)
        entry:
          - title: Detached note
            type: precondition
            identifier: ISO 1
    YAML
  end
end
