# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"

# GATING TEST for suma#94: does the incremental engine (preserve_unresolved +
# artifact_store_dir) survive a *sectionsplit* member? The real SRL collection is
# sectionsplit: true, so the staged per-process build must stage sectionsplit
# sub-collections. collection_sectionsplit_solo.yml is a single sectionsplit
# document whose cross-document reference to an absent sibling is otherwise
# stripped to an "Unresolved reference" message -- exactly the isolated-build case
# preserve mode exists to fix. This test asserts the engine (a) does not crash and
# (b) preserves + stores the stub instead of stripping it.
RSpec.describe "incremental build survives sectionsplit" do
  INPATH = "spec/fixtures/collection"

  around do |ex|
    Dir.mktmpdir { |d| @store = File.join(d, "cache"); ex.run }
  end

  after do
    FileUtils.rm_f %w[action_schemaexpg1.svg cover.html .html.err.html
                      metanorma.asciidoc.log.txt]
  end

  def slug(id)
    id.gsub(%r{[^A-Za-z0-9._-]+}, "-").gsub(/-{2,}/, "-").gsub(/\A-|-\z/, "")
  end

  # Stage +member+ (a docref hash) in isolation into @store: a single-member
  # manifest with preserve + store, so its cross-doc refs to absent siblings are
  # kept as stubs.
  def stage_isolated(member, work, idx)
    man = YAML.load_file("#{INPATH}/collection_sectionsplit.yml")
    man["manifest"]["manifest"] =
      [{ "level" => "subcollection", "title" => "S", "docref" => [member] }]
    one = "#{INPATH}/_ss_rt_#{idx}.yml"
    File.write(one, man.to_yaml)
    Metanorma::Collection.parse(one).render(
      format: %i[xml], output_folder: File.join(work, "iso#{idx}"),
      preserve_unresolved: true, artifact_store_dir: @store,
      compile: { install_fonts: false }
    )
  ensure
    File.delete(one) if one && File.exist?(one)
  end

  it "preserves and stores a sectionsplit member's cross-doc stub without crashing" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    of = File.join(FileUtils.pwd, "spec/fixtures/output")
    col = Metanorma::Collection.parse "#{INPATH}/collection_sectionsplit_solo.yml"

    expect do
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "collection_cover.html",
        compile: { install_fonts: false },
        preserve_unresolved: true,
        artifact_store_dir: @store,
      )
    end.not_to raise_error

    # (a) engine survived sectionsplit + preserve + store.
    # (b) did preserve+store actually engage for the sectionsplit member?
    semantics = Dir[File.join(@store, "*.semantic.xml")]
    expect(semantics).not_to be_empty
    # (c) the absent-sibling cross-doc ref is preserved as a stub (bibitemid kept),
    # not stripped to the "Unresolved reference" text a bare isolated build emits.
    stored = semantics.map { |f| File.read(f) }.join
    expect(stored).to include("bibitemid")

    FileUtils.rm_rf of
  end

  # The full round-trip through sectionsplit: stage every member of a multi-member
  # sectionsplit collection in isolation (preserve + store), then reinflate a
  # manifest of the stored stubs and confirm (1) the sectionsplit member is
  # re-split, (2) its preserved cross-document stub resolves to a real link,
  # (3) no reference is left unresolved, and (4) the attachment is carried
  # through and its reference resolved. Members are identified by their real
  # docid (which is how the orchestration builds the reinflate manifest).
  it "reinflates staged sectionsplit stubs into resolved links, carrying attachments" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    members = [
      { "fileref" => "rice-en.final.xml",  "identifier" => "ISO 17301-1:2016", "sectionsplit" => true },
      { "fileref" => "dummy.xml",          "identifier" => "ISO 17302:2016" },
      { "fileref" => "rice1-en.final.xml", "identifier" => "ISO 1701:1974" },
      { "fileref" => "rice-amd.final.xml", "identifier" => "ISO 17301-1:2016/Amd.1:2017" },
    ]

    Dir.mktmpdir do |work|
      members.each_with_index { |m, i| stage_isolated(m, work, i) }

      # Reinflation manifest: the stored stubs + the attachment.
      reinf = File.join(work, "reinf")
      FileUtils.mkdir_p(File.join(reinf, "pics"))
      FileUtils.cp("#{INPATH}/pics/action_schemaexpg1.svg",
                   File.join(reinf, "pics", "action_schemaexpg1.svg"))
      docrefs = members.map do |m|
        stored = Dir[File.join(@store, "#{slug(m['identifier'])}.*.semantic.xml")].first
        name = "#{slug(m['identifier'])}.xml"
        FileUtils.cp(stored, File.join(reinf, name))
        dr = { "fileref" => name, "identifier" => m["identifier"] }
        dr["sectionsplit"] = true if m["sectionsplit"]
        dr
      end
      attach = { "level" => "attachments", "title" => "Attachments", "docref" =>
        [{ "fileref" => "pics/action_schemaexpg1.svg",
           "identifier" => "action_schemaexpg1.svg", "attachment" => true }] }
      man = YAML.load_file("#{INPATH}/collection_sectionsplit.yml")
      man["manifest"]["manifest"] =
        [{ "level" => "subcollection", "title" => "S", "docref" => docrefs }, attach]
      File.write(File.join(reinf, "reinflate.yml"), man.to_yaml)

      Dir.chdir(reinf) do
        expect do
          Metanorma::Collection.parse("reinflate.yml").render(
            format: %i[xml html], output_folder: "_site", reinflate: true,
            compile: { install_fonts: false }
          )
        end.not_to raise_error
      end

      site = File.join(reinf, "_site")
      rice_parts = Dir[File.join(site, "ISO-17301-1-2016.xml.*.html")]
        .reject { |f| f.include?(".err.") }
      expect(rice_parts).not_to be_empty # (1) rice re-split at reinflation
      rice_html = rice_parts.map { |f| File.read(f) }.join("\n")
      # (2) preserved cross-doc stub -> resolved link
      expect(rice_html).to match(%r{<a href="[^"]*Amd[^"]*\.html">})
      # (3) no dangling references (present siblings + attachment all resolved)
      expect(rice_html).not_to include("Unresolved reference")
      # (4) attachment reference resolved and file carried into the site
      expect(rice_html).to match(%r{href="[^"]*action_schemaexpg1[^"]*"})
      expect(File.exist?(File.join(site, "pics", "action_schemaexpg1.svg"))).to be true
    end
  end
end
