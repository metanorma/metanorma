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
end
