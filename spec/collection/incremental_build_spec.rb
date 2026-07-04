# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"

# Incremental, resumable collection build: compile each member in isolation with
# its cross-document references preserved as stubs and written to a durable,
# content-addressed store; then reinflate a manifest of those stored stubs so the
# references resolve -- native to the collection layer, on the Semantic XML.
RSpec.describe "incremental collection build" do
  INC = File.expand_path("../fixtures/collection/incremental", __dir__)
  MEMBERS = { "ISO 99000-1:2024" => "part1", "ISO 99000-2:2024" => "part2" }.freeze

  def slug(ident)
    ident.gsub(/[^A-Za-z0-9._-]+/, "-").gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
  end

  # Isolated compile of every member, preserving cross-doc stubs into +store+.
  def compile_isolated(store, out)
    Dir.chdir(INC) do
      Metanorma::Collection.parse("collection.yml").render(
        format: %i[xml], output_folder: out,
        preserve_unresolved: true, artifact_store_dir: store
      )
    end
  end

  # Reinflate: assemble a manifest of the stored stub semantics and resolve them.
  def reinflate(store, dir)
    FileUtils.mkdir_p(dir)
    docrefs = MEMBERS.map do |ident, name|
      stored = Dir[File.join(store, "#{slug(ident)}.*.semantic.xml")].first
      FileUtils.cp(stored, File.join(dir, "#{name}.xml"))
      { "fileref" => "#{name}.xml", "identifier" => ident }
    end
    man = YAML.load_file(File.join(INC, "collection.yml"))
    man["manifest"]["manifest"][0]["docref"] = docrefs
    File.write(File.join(dir, "reinflate.yml"), man.to_yaml)
    Dir.chdir(dir) do
      Metanorma::Collection.parse("reinflate.yml").render(
        format: %i[xml html], output_folder: "_site", reinflate: true
      )
    end
    File.join(dir, "_site")
  end

  around { |ex| Dir.mktmpdir { |d| @dir = d; ex.run } }
  let(:store) { File.join(@dir, "cache") }

  it "preserves each member's cross-doc stub into the content-addressed store" do
    compile_isolated(store, File.join(@dir, "iso"))
    semantics = Dir[File.join(store, "*.semantic.xml")]
    expect(semantics.size).to eq 2
    part1 = semantics.find { |f| f.include?("ISO-99000-1") }
    expect(File.read(part1)).to include('bibitemid="part2')
    expect(Dir[File.join(store, "*.anchors.json")].size).to eq 2
  end

  it "reinflates the stored stubs into resolved cross-document links" do
    compile_isolated(store, File.join(@dir, "iso"))
    site = reinflate(store, File.join(@dir, "reinf"))
    part1 = File.read(File.join(site, "part1.html"))
    expect(part1).to include('href="part2.html"')
    expect(part1).not_to include("Unresolved reference")
  end

  it "resumes and is idempotent: a second isolated build skips and rewrites nothing" do
    compile_isolated(store, File.join(@dir, "iso1"))
    before = Dir[File.join(store, "*")].to_h { |f| [f, File.mtime(f)] }
    compile_isolated(store, File.join(@dir, "iso2"))
    after = Dir[File.join(store, "*")].to_h { |f| [f, File.mtime(f)] }
    expect(after).to eq(before)
  end
end
