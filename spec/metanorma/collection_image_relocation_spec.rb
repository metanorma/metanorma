# frozen_string_literal: true

require_relative "../spec_helper"
require "digest"
require "zlib"

# Renders a tiny deterministic PNG of one solid colour.
def png_chunk(type, data)
  [data.size].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
end

def solid_png(rgb)
  ihdr = png_chunk("IHDR", [2, 2, 8, 2, 0, 0, 0].pack("NNC5"))
  row = ("\x00".b + rgb.pack("C3")) * 2
  idat = png_chunk("IDAT", Zlib::Deflate.deflate(row))
  ("\x89PNG\r\n\x1a\n".b + ihdr + idat + png_chunk("IEND", "".b))
end

def real_png
  solid_png([255, 0, 0])
end

def decoy_a_png
  solid_png([0, 255, 0])
end

def decoy_b_png
  solid_png([0, 0, 255])
end

def relocation_member_xml
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <metanorma xmlns="https://www.metanorma.org/ns/standoc" flavor="iso">
    <bibdata type="standard">
    <title language="en" format="text/plain" type="main">Fig document</title>
    <title language="en" format="text/plain" type="title-main">Fig document</title>
    <docidentifier primary="true" type="ISO">ISO 99999:2016</docidentifier>
    <docnumber>99999</docnumber>
    <language>en</language>
    <script>Latn</script>
    <status>
    <stage abbreviation="IS">60</stage>
    <substage>60</substage>
    </status>
    <copyright>
    <from>2016</from>
    <owner>
    <organization>
    <name>International Organization for Standardization</name>
    </organization>
    </owner>
    </copyright>
    <ext>
    <doctype>international-standard</doctype>
    </ext>
    </bibdata>
    <sections>
    <clause id="_scope" type="scope"><title id="_scope-t">Scope</title>
    <p id="_p1">This document embeds a figure.</p>
    <figure id="_fig-1">
    <name id="_fig-1-t">Fig 1</name>
    <image id="_img-1" src="../img/fig.png" mimetype="image/png" \
    height="auto" width="auto" alt="Fig"/>
    </figure>
    </clause>
    </sections>
    </metanorma>
  XML
end

def relocation_manifest_yaml
  <<~YAML
    directives:
      - documents-inline
      - flavor: iso
    bibdata:
      title:
        type: title-main
        language: en
        content: Fig Collection
      type: collection
      docid:
        type: iso
        id: 4400x
    manifest:
      identifier: figcollection-manifest
      level: collection
      title: Fig Collection
      docref:
        - fileref: ../doc/fig.xml
          identifier: ISO 99999:2016
          index: true
    format:
      - presentation
      - xml
      - html
  YAML
end

def strip_heading_ids(html)
  guid = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
  html.gsub(/ id="_#{guid}"/o, ' id="_"')
    .gsub(/ href="#_#{guid}"/o, ' href="#_"')
end

def byte_identical_outputs?(outs, files)
  files.all? do |f|
    File.binread(File.join(outs["a"], f)) ==
      File.binread(File.join(outs["b"], f))
  end
end

RSpec.describe Metanorma::Collection do
  # metanorma#646: the collection renderer's image relocation must resolve
  # image targets against the emitting document's directory. Vectory's
  # datauri fallback tries the process working directory first, so identical
  # sources built from two directories used to inline different images --
  # each build picked whatever file the working directory happened to place
  # at the target's relative path. Each render below runs from a different
  # working directory carrying a different decoy image exactly where
  # working-directory resolution looks; all builds must embed the fixture
  # image next to the document, and their output must be byte-identical.
  describe "image relocation anchors at the emitting document directory" do
    let(:build_outputs) do
      root = FileUtils.pwd
      work = File.join(root, "work")
      %w[a b].each do |tag|
        dirs = [File.join(work, "tree", "img"), File.join(work, "tree", "doc"),
                File.join(work, "tree", "col"), File.join(work, tag, "wd"),
                File.join(work, tag, "img")]
        FileUtils.mkdir_p(dirs)
        File.binwrite(File.join(work, "tree", "img", "fig.png"), real_png)
        File.write(File.join(work, "tree", "doc", "fig.xml"),
                   relocation_member_xml)
        File.write(File.join(work, "tree", "col", "collection.yml"),
                   relocation_manifest_yaml)
        File.binwrite(File.join(work, tag, "img", "fig.png"),
                      tag == "a" ? decoy_a_png : decoy_b_png)
      end

      %w[a b].each_with_object({}) do |tag, h|
        out = File.join(work, "out-#{tag}")
        Dir.chdir(File.join(work, tag, "wd")) do
          described_class
            .parse(File.join(work, "tree", "col", "collection.yml"))
            .render(format: %i[presentation xml html], output_folder: out,
                    compile: { install_fonts: false })
        end
        h[tag] = out
      end
    end

    it "inlines the image beside the document, not beside the build" do
      member = File.read(File.join(build_outputs["a"],
                                   "doc/fig.presentation.xml"))
      # The image src is a single data URI: containing the fixture image's
      # bytes means the working-directory decoy did not get embedded.
      expected = %(src="data:image/png;base64,#{[real_png].pack('m0')}")
      expect(member).to include(expected)
    end

    it "renders byte-identical XML output from two build directories" do
      files = %w[fig.xml collection.xml collection.presentation.xml
                 doc/fig.presentation.xml]
      expect(byte_identical_outputs?(build_outputs, files)).to be(true)
    end

    # isodoc assigns random heading ids in HTML output (isodoc#861); that
    # nondeterminism is independent of image relocation.
    it "renders HTML identical apart from the random heading ids" do
      outs = build_outputs
      html_a = File.read(File.join(outs["a"], "doc/fig.html"))
      html_b = File.read(File.join(outs["b"], "doc/fig.html"))
      expect(strip_heading_ids(html_a)).to eq(strip_heading_ids(html_b))
    end
  end
end
