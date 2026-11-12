# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"
require "nokogiri"

# svgmap erefs bind through the registered reference-anchor resolvers at
# EVERY render stage — including plain (non-reinflate) renders. Schema-doc
# pages carry synthesized svgmap items (expressir 2.4.64+ formats the
# __expressg remark with its item list) and render outside the reinflate;
# without the always-on pass their hotspots emit as bare unbound links
# (iso-10303#844).
RSpec.describe "svgmap erefs bind through resolvers at every stage" do
  let(:doc_fixture) { "spec/fixtures/collection/rice-en.final.norepo.xml" }
  let(:outpath) { File.join(@work, "out") }

  around do |ex|
    Dir.mktmpdir do |d|
      @work = d
      ex.run
    end
  end

  after do
    Metanorma::Collection::Renderer.reference_anchor_resolvers.reject! do |r|
      r.inspect.include?("svgmap-resolver-spec")
    end
  end

  # The spec_helper around-hook mirrors spec/fixtures into a per-example
  # temp tree and runs the example with cwd at its root, so the manifest
  # parses by its relative path and its filerefs resolve inside the
  # mirror. The injected svgmap replaces the rice fixture in place; no
  # manifest rewrite needed.
  def build_work_collection
    xml = File.read(doc_fixture)
    svgmap = <<~XML
      <svgmap id='svg-repro'>
        <figure id='fig-repro'>
          <image src='hotspot_schemaexpg1.svg' mimetype='image/svg+xml'/>
        </figure>
        <target href='mn://repro'>
          <eref bibitemid='express_repro_target'>repro</eref>
        </target>
      </svgmap>
    XML
    # The svgmap eref names a bibliography bibitem, not a page anchor, so
    # Stage 1 leaves it for the resolver pass; the bibitem must exist for
    # the references render to succeed.
    bibitem = <<~XML
      <bibitem id='express_repro_target' type='standard'>
        <title format='text/plain' language='en' script='Latn'>Resolver target</title>
        <docidentifier type='metanorma'>repro</docidentifier>
        <docnumber>1</docnumber>
        <date type='published'><on>2026</on></date>
        <contributor>
          <role type='publisher'/>
          <organization><name>ISO</name><abbreviation>ISO</abbreviation></organization>
        </contributor>
        <language>en</language>
        <script>Latn</script>
      </bibitem>
    XML
    injected = xml.sub("</references>", "#{bibitem}</references>")
                  .sub("</metanorma>",
                       "<p id='resolver-bound-anchor'>repro</p>" \
                       "#{svgmap}</metanorma>")
    raise "svgmap injection no-op" if xml == injected

    File.write(doc_fixture, injected)
  end

  def register_resolver
    resolver = ->(bibitemid, _lookup) {
      next unless bibitemid == "express_repro_target"

      { key: "repro-doc", url: "member.html",
        id: "resolver-bound-anchor" }
    }
    def resolver.inspect
      "svgmap-resolver-spec"
    end
    Metanorma::Collection::Renderer
      .register_reference_anchor_resolver(&resolver)
  end

  it "binds svgmap erefs in a plain render through the resolver" do
    build_work_collection
    register_resolver

    Metanorma::Collection.parse(
      "spec/fixtures/collection/collection1.norepo.yml"
    ).render(
      format: %i[presentation xml], output_folder: outpath,
      compile: { install_fonts: false },
    )

    xml = File.read(File.join(outpath, "member.xml"))
    expect(xml).to include("resolver-bound-anchor")
    expect(xml).to include('target="#resolver-bound-anchor"')
  end
end
