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
  let(:base_manifest) { "spec/fixtures/collection/collection1.norepo.yml" }
  let(:svg_fixture) { "spec/fixtures/collection/hotspot_schemaexpg1.svg" }
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
    injected = xml.sub("</iso-standard>",
                       "<p id='resolver-bound-anchor'>repro</p>" \
                       "#{svgmap}</iso-standard>")
    File.write(File.join(@work, "member.xml"), injected)
    FileUtils.cp(svg_fixture, File.join(@work, "hotspot_schemaexpg1.svg"))

    man = YAML.load_file(base_manifest)
    man["manifest"]["docref"] =
      [{ "fileref" => "member.xml", "identifier" => "ISO 17301-1" }]
    File.write(File.join(@work, "manifest.yml"), man.to_yaml)
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

    Dir.chdir(@work) do
      Metanorma::Collection.parse("manifest.yml").render(
        format: %i[presentation xml], output_folder: outpath,
        compile: { install_fonts: false },
      )
    end

    xml = File.read(File.join(outpath, "member.xml"))
    expect(xml).to include("resolver-bound-anchor")
    expect(xml).to include('target="#resolver-bound-anchor"')
  end
end
