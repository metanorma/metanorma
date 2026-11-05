# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"
require "nokogiri"

INPATH = "spec/fixtures/collection"

# Reinflated section-split renders must carry the inline-SVG (EXPRESS-G)
# figures their svgmaps hold, each exactly once, with hotspot anchors that
# resolve (metanorma#656).
#
# The staged artefact store keeps the compile-time svgmap state: storing the
# Vectory-processed tree would bake the staging build's suffix and the
# extracted semx companion copies into the stored svgmaps, and the reinflate
# render would then process already-processed svgmaps -- figures render twice
# (the stored companion next to its simplified original) and the SVG hotspot
# hrefs carry dead, stale-suffix anchors. The reinflate render itself
# resolves the svgmaps as a plain build does, drops the unresolved
# anchor-type companions of svgmap targets, and re-keys hotspot anchors to
# the member page that carries the declaration.
RSpec.describe "reinflate svgmap figures and hotspots" do
  around do |ex|
    Dir.mktmpdir do |d|
      @store = File.join(d, "cache")
      ex.run
    end
  end

  # split-file byproducts are written beside the member fixture
  after do
    FileUtils.rm_f %w[hotspot_schemaexpg1.svg cover.html index.html
                      .html.err.html metanorma.asciidoc.log.txt]
    FileUtils.rm_f Dir["#{INPATH}/rice_hotspot.final.xml.*"]
      .reject { |f| f.end_with?(".final.xml") }
    FileUtils.rm_rf "spec/fixtures/output"
  end

  # Stage the sectionsplit member under an identifier whose NCName differs
  # from the one reinflation resolves ("rice-stage" vs "ISO 17301-1"), the
  # corpus shape.
  def stage_isolated(work)
    one = "#{INPATH}/_reinf_svgmap_stage.yml"
    File.write(one, manifest_with_docref(
      "fileref" => "rice_hotspot.final.xml",
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

  def stored_parent
    Dir[File.join(@store, "rice-stage.[0-9a-f]*.semantic.xml")]
      .reject { |f| f.include?("-Scope-") || f.include?("-Bibliography-") }
      .first
  end

  def reinflate(work)
    reinf = File.join(work, "reinf")
    FileUtils.mkdir_p(reinf)
    FileUtils.cp(stored_parent, File.join(reinf, "rice_hotspot.xml"))
    # the svgmap image src resolves against the render's member directory
    FileUtils.cp("#{INPATH}/hotspot_schemaexpg1.svg",
                 File.join(reinf, "hotspot_schemaexpg1.svg"))
    File.write(File.join(reinf, "reinflate.yml"), manifest_with_docref(
      "fileref" => "rice_hotspot.xml",
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

  def manifest_with_docref(docref)
    man = YAML.load_file("#{INPATH}/collection_sectionsplit.yml")
    man["manifest"]["manifest"] =
      [{ "level" => "subcollection", "title" => "S", "docref" => [docref] }]
    man
  end

  def rice_pages
    Dir[File.join(@site, "rice_hotspot.xml.*.html")]
      .reject { |f| f.include?(".err.") }
  end

  def svg_hotspot_hrefs
    rice_pages.each_with_object([]) do |f, m|
      doc = Nokogiri::HTML(File.read(f))
      doc.xpath("//*[local-name()='svg']//*[local-name()='a'][@href]")
        .each { |a| m << [f, a["href"]] }
    end
  end

  def fragment_ids(page)
    Nokogiri::HTML(File.read(page)).xpath("//*[@id or @name]")
      .map { |n| n["id"] || n["name"] }
  end

  it "renders each svgmap figure once with resolvable hotspot anchors" do
    FileUtils.cp "#{INPATH}/hotspot_schemaexpg1.svg", "hotspot_schemaexpg1.svg"
    @site = File.join(FileUtils.pwd, "spec/fixtures/output")

    Dir.mktmpdir do |work|
      stage_isolated(work)
      reinflate(work)
    end

    parts = rice_pages
    expect(parts).not_to be_empty # the member re-splits at reinflation

    # (1) the svgmap figure renders, exactly once across the split pages
    svg_figures = parts.sum do |f|
      doc = Nokogiri::HTML(File.read(f))
      doc.xpath("//*[local-name()='figure']")
        .count { |fig| !fig.xpath(".//*[local-name()='svg']").empty? }
    end
    expect(svg_figures).to eq(1)

    # (2) no dead anchor-type hotspot hrefs: the svgmap eref companions
    # never become bibitemid fragments inside the SVGs
    expect(svg_hotspot_hrefs.map(&:last))
      .not_to include(match(/#[A-Z]{8}_/))

    # (3) every fragment link on an SVG hotspot resolves on its target page
    svg_hotspot_hrefs.each do |f, href|
      page, frag = href.match(/\A([^#]*)#(.+)\z/)&.captures
      next unless frag # bare ordinal hrefs are the svgmap list mapping
      target = page ? File.expand_path(page, File.dirname(f)) : f
      expect(File.exist?(target)).to be true
      expect(fragment_ids(target)).to include(frag)
    end

    # (4) the #thirdclause hotspot is re-keyed to the section page that
    # carries the clause declaration, under its full rendered id
    hotspot = svg_hotspot_hrefs.map(&:last)
      .find { |h| h.include?("thirdclause") }
    expect(hotspot).not_to be_nil
    page, frag = hotspot.match(/\A([^#]*)#(.+)\z/)&.captures
    expect(frag).to match(/\Athirdclause_/)
    target = page ? File.expand_path(page, @site) : @site
    expect(File.exist?(target)).to be true
    expect(fragment_ids(target)).to include(frag)
  end
end
