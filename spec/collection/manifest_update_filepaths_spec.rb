# frozen_string_literal: true

require "spec_helper"

RSpec.describe Metanorma::Collection::Manifest do
  # A docref pointing at a nested collection YAML expands into the
  # sub-manifest's `entry` collection, which update_filepaths receives
  # directly as an Array; entries within it still get their filepaths
  # prefixed (regression: undefined method `file' for an instance of
  # Array, hit by the iso-10303 nested manifests).
  def updater
    described_class.allocate
  end

  def entries_from(yaml)
    Metanorma::Collection::Config::Config.from_yaml(yaml).manifest.entry
  end

  it "prefixes filepaths through a bare Array of entries" do
    entries = entries_from(<<~YAML)
      manifest:
        entry:
          - file: documents/iso-10303-41/document.adoc
          - file: documents/iso-10303-42/document.adoc
    YAML

    updater.send(:update_filepaths, entries, "prefix")
    expect(entries.first.file.to_s)
      .to eq("prefix/documents/iso-10303-41/document.adoc")
    expect(entries.last.file.to_s)
      .to eq("prefix/documents/iso-10303-42/document.adoc")
  end

  it "prefixes filepaths of entries nested in a sub-manifest" do
    nested = entries_from(<<~YAML)
      manifest:
        entry:
          - level: document
            docref:
              - file: documents/a.adoc
    YAML

    updater.send(:update_filepaths, nested, "pfx")
    expect(nested.first.entry.first.file.to_s).to eq("pfx/documents/a.adoc")
  end
end
