# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"
require "nokogiri"

# iso-10303#875: a flavor's reference-anchor resolver binds svgmap
# hotspots at EVERY stage - including the preserve-mode isolated render.
# The baked hrefs then carry that render's anchor suffixes, and the
# reinflate render must re-key them onto the final anchors. This spec
# registers a resolver that mimics the flavor (metanorma-iso binds
# express-reference hotspots to schema-declaration anchors) and pins
# the round trip.
#
# The reinflate keys differ from the stage keys, as they do in the
# corpus (the stage manifest keys each part by its slug, the reinflate
# manifest by the document identifier): the baked href suffix
# (iso99000-1) matches no final id (ISO_99000-1_2024 chains), and the
# re-key must resolve the shared stem to bind the hotspot.
RSpec.describe "svgmap hotspot rekey across isolate and reinflate" do
  INC = File.expand_path("../fixtures/collection/incremental", __dir__)

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  # A resolver like metanorma-iso's: bibitem ids named after the express
  # reference resolve to an anchor record whose id carries the CURRENT
  # render's anchor suffix scheme - here the docid NCName, as the flavor
  # does. (The compile sanitizes the cite's bibitemid: colons become
  # underscores and the render suffix is appended.)
  let(:resolver) do
    lambda do |bibitemid, _lookup|
      return nil unless bibitemid.include?("express_fastener")

      { key: "iso99000-1",
        id: "target_declaration_#{bibitemid.sub(/_iso99000-1\z/, '')}_iso99000-1",
        url: nil }
    end
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  it "re-keys resolver-bound hotspots onto the final anchors" do
    Metanorma::Collection::Renderer
      .register_reference_anchor_resolver(&resolver)

    work = File.join(@dir, "work")
    FileUtils.cp_r(INC, work)
    # An svgmap whose eref names the express reference, bound by the
    # resolver at stage time.
    write(File.join(work, "documents/part1-terms.adoc"),
          <<~ADOC)
      = Toy fasteners — Terms and definitions
      :docnumber: 99000
      :partnumber: 1
      :edition: 1
      :revdate: 2024-01-01
      :copyright-year: 2024
      :language: en
      :title-intro-en: Toy fasteners
      :title-main-en: Terms and definitions
      :doctype: international-standard
      :mn-document-class: iso
      :mn-output-extensions: xml,html

      == Scope

      Terms are applied by the bolt specification in <<part2>>.

      [bibliography]
      == Normative references

      * [[[part2,repo:(current-metanorma-collection/toy,ISO 99000-2:2024)]]]
      * [[[express:fastener,repo:(current-metanorma-collection/toy,ISO 99000-1:2024)]]]

      == Terms and definitions

      [[target_declaration_express_fastener]]
      === fastener

      device that mechanically joins two or more objects

      [[bolt-figure]]
      [.svgmap]
      ====
      image::bolt_structure.svg[]

      * <<express:fastener>>; A
      ====
    ADOC
    # The source SVG wraps its shape with the ordinal marker.
    write(File.join(work, "documents/bolt_structure.svg"),
          <<~SVG)
      <svg xmlns="http://www.w3.org/2000/svg">
        <a href="A"><rect id="bolt-head"/></a>
      </svg>
    SVG

    # Stage under slug identifiers, as the corpus's stage manifests do;
    # reinflation below re-keys under the document identifiers.
    man = YAML.load_file(File.join(work, "collection.yml"))
    man["manifest"]["manifest"][0]["docref"] = [
      { "fileref" => "documents/part1-terms.adoc", "identifier" => "iso99000-1" },
      { "fileref" => "documents/part2-bolts.adoc", "identifier" => "iso99000-2" },
    ]
    File.write(File.join(work, "collection.yml"), man.to_yaml)

    store = File.join(@dir, "cache")
    Dir.chdir(work) do
      Metanorma::Collection.parse("collection.yml").render(
        format: %i[xml], output_folder: "iso",
        preserve_unresolved: true, artifact_store_dir: store
      )
    end

    # The stage bake: the stored semantic XML carries the hotspot href
    # under the STAGE render's anchor scheme. This is the defect's
    # starting point - the href names an id that no reinflate render
    # will produce.
    stored = Dir[File.join(store, "*.semantic.xml")]
      .map { |f| File.read(f) }
      .find { |x| x.include?("bolt-head") }
    expect(stored)
      .to include('href="#target_declaration_express_fastener_iso99000-1"')

    # The reinflate keys differ from the stage keys, as they do in the
    # corpus: the stored hrefs name ids under the stage scheme, while
    # this render's split sections carry the identifier's suffix chain.
    docrefs = {
      "ISO 99000-1:2024" => "part1", "ISO 99000-2:2024" => "part2"
    }.filter_map do |ident, name|
      stored = Dir[File.join(store, "#{name.sub('part', 'iso99000-')}.*.semantic.xml")].first
      next unless stored

      FileUtils.cp(stored, File.join(work, "#{name}.xml"))
      { "fileref" => "#{name}.xml", "identifier" => ident }
    end
    man = YAML.load_file(File.join(work, "collection.yml"))
    man["manifest"]["sectionsplit"] = true
    man["manifest"]["manifest"][0]["docref"] = docrefs
    File.write(File.join(work, "reinflate.yml"), man.to_yaml)
    Dir.chdir(work) do
      Metanorma::Collection.parse("reinflate.yml").render(
        format: %i[xml html], output_folder: "_site", reinflate: true
      )
    end

    figure_page = Dir[File.join(work, "_site", "**", "*.html")]
      .reject { |f| f.include?(".err.") }
      .find { |f| File.read(f).include?("bolt-head") }
    expect(figure_page).not_to be_nil
    html = File.read(figure_page)
    # The hotspot survives with a live href, pointing at the real
    # declaration anchor of THIS render - not at a stage-baked id, and
    # not at the root-type-stamped composition the unguided remap
    # produces.
    anchor = html[/id="(target_declaration_express_fastener[^"]*)"/, 1]
    expect(anchor).to be_a(String)
    svg_hrefs = Nokogiri::HTML(html)
      .xpath("//*[local-name()='svg']//*[local-name()='a'][@href]")
      .map { |a| a["href"] }
    expect(svg_hrefs).to eq(["##{anchor}"])
  ensure
    Metanorma::Collection::Renderer.reference_anchor_resolvers.clear
  end
end
