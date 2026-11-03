# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"

# Regression: only_members (distributed reinflation) must not drop a
# selected member's section-split outputs. Section-split instances are
# added to the file lookup at renderer init under their own entry keys,
# each carrying :parentid - a membership check that only knows the
# docref identifiers skips every one of them, so the sliced site ships
# index pages whose section pages are missing (iso-10303#811's 52 KB
# artifact: 43 index pages, zero section pages).
RSpec.describe "only_members with sectionsplit" do
  INPATH = "spec/fixtures/collection"

  after do
    FileUtils.rm_f %w[action_schemaexpg1.svg cover.html .html.err.html
                      metanorma.asciidoc.log.txt]
  end

  def render_selected(members)
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    out = File.join(FileUtils.pwd, "spec/fixtures/output")
    FileUtils.rm_rf out
    Metanorma::Collection.parse("#{INPATH}/collection_sectionsplit.yml")
      .render(
        format: %i[xml html], output_folder: out,
        coverpage: "collection_cover.html",
        compile: { install_fonts: false },
        only_members: members,
      )
    out
  end

  it "renders the selected sectionsplit member's split outputs" do
    out = render_selected(["ISO 17301-1:2016"])

    split_parts = Dir[File.join(out, "rice-en.final.xml.*.html")]
      .reject { |f| f.include?(".err.") }
    expect(split_parts).not_to be_empty
  ensure
    FileUtils.rm_rf out
  end

  it "still excludes members outside the selection" do
    out = render_selected(["ISO 17301-1:2016"])

    expect(Dir[File.join(out, "dummy*")]).to be_empty
  ensure
    FileUtils.rm_rf out
  end

  # The corpus's actual shape: docrefs that declare no identifier get GUID
  # placeholders assigned at manifest load, which manifest_identifier then
  # resolves into real docids (the file lookup keys entries by those). A
  # caller passing the raw GUIDs as only_members - what suma's staged
  # reinflate does - matched nothing and hollowed the site.
  it "selects by the GUID placeholders assigned to identifier-less docrefs" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    out = File.join(FileUtils.pwd, "spec/fixtures/output")
    FileUtils.rm_rf out
    col = Metanorma::Collection.parse("#{INPATH}/collection_sectionsplit_noid.yml")
    guids = col.manifest.identifier_aliases.keys
    expect(guids).not_to be_empty

    col.render(
      format: %i[xml html], output_folder: out,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
      only_members: guids,
    )

    split_parts = Dir[File.join(out, "rice-en.final.xml.*.html")]
      .reject { |f| f.include?(".err.") }
    expect(split_parts).not_to be_empty
  ensure
    FileUtils.rm_rf out
  end

  it "selects by the resolved docid of an identifier-less docref" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    out = File.join(FileUtils.pwd, "spec/fixtures/output")
    FileUtils.rm_rf out
    col = Metanorma::Collection.parse("#{INPATH}/collection_sectionsplit_noid.yml")
    resolved = col.manifest.identifier_aliases.values
    expect(resolved).not_to be_empty

    col.render(
      format: %i[xml html], output_folder: out,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
      only_members: [resolved.first],
    )

    split_parts = Dir[File.join(out, "rice-en.final.xml.*.html")]
      .reject { |f| f.include?(".err.") }
    expect(split_parts).not_to be_empty
  ensure
    FileUtils.rm_rf out
  end
end
