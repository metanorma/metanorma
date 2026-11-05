# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"
require "nokogiri"

INPATH = "spec/fixtures/collection"

# Reinflated section-split pages must carry the ids the render's own
# cross-reference passes compose into cross-section link anchors.
#
# Staging keys the stored ids by the staging identifier; reinflation
# resolves the member under a different identifier. The split pages
# therefore must be re-keyed from the stored suffix to the render's
# suffix chain (parent suffix + split-instance key) — exactly what a
# plain build's add_document_suffix produces. Without the re-key, every
# cross-section fragment link dangles (iso-10303 SRL delivery: 22,431
# broken fragments).
RSpec.describe "reinflate sectionsplit anchor agreement" do
  around do |ex|
    Dir.mktmpdir do |d|
      @store = File.join(d, "cache")
      ex.run
    end
  end

  after do
    FileUtils.rm_f %w[action_schemaexpg1.svg cover.html .html.err.html
                      metanorma.asciidoc.log.txt]
  end

  def manifest_with_docref(docref)
    man = YAML.load_file("#{INPATH}/collection_sectionsplit.yml")
    man["manifest"]["manifest"] =
      [{ "level" => "subcollection", "title" => "S", "docref" => [docref] }]
    man
  end

  # Stage the sectionsplit member under an identifier whose NCName
  # differs from the one reinflation resolves (here: "rice-stage" vs
  # "ISO 17301-1"), the corpus shape.
  def stage_isolated(work)
    one = "#{INPATH}/_reinf_agreement_stage.yml"
    File.write(one, manifest_with_docref(
      "fileref" => "rice-en.final.xml",
      "identifier" => "rice-stage",
      "sectionsplit" => true,
    ).to_yaml)
    Metanorma::Collection.parse(one).render(
      format: %i[xml], output_folder: File.join(work, "stage"),
      preserve_unresolved: true, artifact_store_dir: @store,
      compile: { install_fonts: false }
    )
  ensure
    File.delete(one) if one && File.exist?(one)
  end

  def reinflate(work)
    stored = Dir[File.join(@store, "rice-stage.*.semantic.xml")].first
    reinf = File.join(work, "reinf")
    FileUtils.mkdir_p(reinf)
    FileUtils.cp(stored, File.join(reinf, "rice.xml"))
    File.write(File.join(reinf, "reinflate.yml"), manifest_with_docref(
      "fileref" => "rice.xml",
      "identifier" => "ISO 17301-1",
      "sectionsplit" => true,
    ).to_yaml)

    Dir.chdir(reinf) do
      Metanorma::Collection.parse("reinflate.yml").render(
        format: %i[xml html], output_folder: @site, reinflate: true,
        compile: { install_fonts: false }
      )
    end
  end

  # (target page, fragment) pairs for every same-tree fragment link on
  # the page that has an existing target file.
  def page_fragment_links(page)
    File.read(page).scan(%r{<a[^>]*href="([^"]*)\.html#([^"]*)"})
      .reject { |(tgt, _)| tgt.start_with?("http", "#") }
      .map do |(tgt, frag)|
        [File.join(File.dirname(page), "#{tgt}.html"), frag]
      end
      .select { |(tf, _)| File.exist?(tf) }
  end

  def fragment_ids(page)
    Nokogiri::HTML(File.read(page)).xpath("//*[@id]").map { |n| n["id"] }
  end

  # Every same-tree fragment link between rendered pages must resolve to
  # an id on its target page.
  def broken_fragment_links
    Dir[File.join(@site, "*.html")].reject { |f| f.include?(".err.") }
      .each_with_object([]) do |f, m|
      page_fragment_links(f).each do |(tf, frag)|
        next if fragment_ids(tf).include?(frag)

        m << "#{File.basename(f)} -> #{File.basename(tf)}##{frag}"
      end
    end
  end

  it "renders split pages whose ids equal the cross-section link anchors" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    @site = File.join(FileUtils.pwd, "spec/fixtures/output")
    FileUtils.rm_rf(@site)

    Dir.mktmpdir do |work|
      stage_isolated(work)
      reinflate(work)
    end

    parts = Dir[File.join(@site, "rice.xml.*.html")]
      .reject { |f| f.include?(".err.") }
    expect(parts).not_to be_empty # the member re-splits at reinflation

    broken = broken_fragment_links
    expect(broken).to be_empty

    # The agreement is on this render's suffix chain (parent suffix +
    # split-instance key), not on the suffix the store was keyed with.
    rice_html = parts.map { |f| File.read(f) }.join("\n")
    chain = %r{href="rice\.xml\.[^"]*\.html#[^"]*_ISO_17301-1_ISO_17301-1_}
    expect(rice_html).to match(chain)
    # No stage-flavoured LINK TARGETS on anchors (HTML anchors and SVG
    # hotspots alike — the reader-facing links this render re-keys).
    # Vectory's id disambiguation inside the SVGs still carries the
    # stored suffix on clip-path/use self-references, which are
    # self-consistent and reader-invisible; this pins anchor hrefs only.
    # This was green upstream of metanorma#656 only because the figures
    # were absent.
    anchors = Nokogiri::HTML(rice_html).xpath("//a[@href]").map { |a| a["href"] }
    expect(anchors.grep(/rice-stage/)).to be_empty
  ensure
    FileUtils.rm_rf(@site)
  end
end
