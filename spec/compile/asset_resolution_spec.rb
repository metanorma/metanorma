require_relative "../spec_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "compile-time asset resolution" do
  # Member document reaching a sibling include, the form a collection
  # member or plugin emits as docfile-relative asset paths.
  def make_member(root)
    member = File.join(root, "member")
    FileUtils.mkdir_p(member)
    File.write(File.join(member, "inc.adoc"), "Included content here.\n")
    File.write(File.join(member, "doc.adoc"), <<~ASDOC)
      = T

      include::inc.adoc[]
    ASDOC
    member
  end

  def compile_member(docfile, options)
    Metanorma::Compile.new.compile(
      docfile,
      { type: "iso", extension_keys: [:xml], agree_to_terms: true,
        install_fonts: false, novalid: true }.merge(options),
    )
    File.read("#{docfile.sub(/\.adoc$/, "")}.xml", encoding: "utf-8")
  end

  it "prefixes include targets with an absolute docfile directory when base_dir is given" do
    compile = Metanorma::Compile.new
    src = "include::inc.adoc[]\nembed::other.adoc[]\n"
    relative = compile.process_input_adoc_includes(src, "member/doc.adoc")
    expect(relative).to eq(<<~EXPECTED)
      include::member/inc.adoc[]
      embed::member/other.adoc[]
    EXPECTED
    absolute = compile.process_input_adoc_includes(
      src, "member/doc.adoc", "member"
    )
    expect(absolute).to eq(<<~EXPECTED)
      include::#{File.expand_path("member")}/inc.adoc[]
      embed::#{File.expand_path("member")}/other.adoc[]
    EXPECTED
  end

  it "resolves docfile-relative includes when compiled from the collection root without base_dir" do
    Dir.mktmpdir do |root|
      member = make_member(root)
      Dir.chdir(root) do
        xml = compile_member("member/doc.adoc", {})
        expect(xml).to include("Included content here.")
        expect(xml).not_to include("Unresolved directive")
      end
    end
  end

  it "loses docfile-relative includes when compiled from a foreign working directory without base_dir" do
    Dir.mktmpdir do |root|
      member = make_member(root)
      elsewhere = File.join(root, "elsewhere")
      FileUtils.mkdir_p(elsewhere)
      docfile = File.join(member, "doc.adoc")
      Dir.chdir(elsewhere) do
        xml = compile_member(docfile, {})
        # The include jail sits at the working directory, so the
        # docfile-anchored include target is recovered into it and lost:
        # the default this issue documents.
        expect(xml).to include("Unresolved directive")
        expect(xml).not_to include("Included content here.")
      end
    end
  end

  it "resolves docfile-relative includes from a foreign working directory with base_dir" do
    Dir.mktmpdir do |root|
      member = make_member(root)
      elsewhere = File.join(root, "elsewhere")
      FileUtils.mkdir_p(elsewhere)
      docfile = File.join(member, "doc.adoc")
      Dir.chdir(elsewhere) do
        xml = compile_member(docfile, base_dir: member)
        expect(xml).to include("Included content here.")
        expect(xml).not_to include("Unresolved directive")
      end
    end
  end

  it "resolves docfile-relative includes from a relative docfile path with base_dir" do
    Dir.mktmpdir do |root|
      make_member(root)
      Dir.chdir(root) do
        xml = compile_member("member/doc.adoc", base_dir: "member")
        expect(xml).to include("Included content here.")
        expect(xml).not_to include("Unresolved directive")
      end
    end
  end
end
