# frozen_string_literal: true

require "spec_helper"
require "yaml"

# Requiring the metanorma gem must not configure the host process:
# the collection config flipped Lutaml::Model's XML adapter to
# :nokogiri at module-load time, overriding every consumer's engine
# choice and dragging the nokogiri lane's namespaced-children parsing
# bug (lutaml-model#1212) into every metanorma run
# (metanorma#749, metanorma#745). The manifest config now parses on
# lutaml-model's default resolution - the moxml facade, leptris engine
# preferred when present; the host decides the engine.
RSpec.describe Metanorma::Collection::Config::Manifest do
  subject(:manifest) { described_class.from_yaml(manifest_yaml) }

  let(:manifest_source) do
    File.read(
      File.expand_path("../../../../lib/metanorma/collection/config/" \
                       "manifest.rb", __dir__),
    )
  end

  let(:manifest_yaml) do
    {
      "directives" => ["documents-inline"],
      "bibdata" => {
        "title" => { "content" => "Coll" },
        "type" => "collection",
      },
      "docref" => [
        { "fileref" => "documents/p1/document.adoc",
          "identifier" => "ISO 1", "sectionsplit" => true },
      ],
    }.to_yaml
  end

  it "does not configure Lutaml::Model at load time" do
    expect(manifest_source).not_to include("Lutaml::Model::Config.configure")
  end

  it "parses bibdata on the default adapter lane" do
    expect(manifest.bibdata.title.first.content).to eq("Coll")
  end

  it "parses docrefs on the default adapter lane" do
    expect(manifest.entry.first.identifier).to eq("ISO 1")
  end

  it "carries the docref flags through" do
    expect(manifest.entry.first.sectionsplit).to be(true)
  end
end
