# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "open3"
require "tmpdir"

# Change-aware collection builds (metanorma-cli#495): with changed_since,
# a member whose sources did not change since a git ref keeps its existing
# output; only the changed members are compiled again.
RSpec.describe "collection changed_since" do
  fixtures = File.expand_path("../fixtures/collection", __dir__)

  def git(dir, *args)
    out, status = Open3.capture2e(
      "git", "-C", dir, "-c", "user.name=spec",
      "-c", "user.email=spec@example.com", "-c", "commit.gpgsign=false",
      *args
    )
    status.success? or raise "git #{args.join(' ')}: #{out}"
    out
  end

  def repo(dir, files)
    files.each do |name, text|
      path = File.join(dir, name)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "commit", "-q", "-m", "base")
    git(dir, "tag", "base")
  end

  describe Metanorma::Collection::ChangeSet do
    around do |ex|
      Dir.mktmpdir do |d|
        @dir = d
        ex.run
      end
    end

    before do
      repo(@dir, "a.adoc" => "= A\n\ninclude::parts/one.adoc[]\n",
                 "parts/one.adoc" => "one\n",
                 "b.adoc" => "= B\n\ninclude::{attr}/x.adoc[]\n",
                 "b.xml" => "<b/>", "c.xml" => "<c/>")
    end

    def change_set
      described_class.new("base", @dir)
    end

    it "reports no change for a clean tree" do
      %w[a.adoc b.xml c.xml].each do |f|
        expect(change_set.changed?(File.join(@dir, f))).to be false
      end
    end

    it "counts a change in an included file, transitively" do
      File.write(File.join(@dir, "parts/one.adoc"), "two\n")
      expect(change_set.changed?(File.join(@dir, "a.adoc"))).to be true
      expect(change_set.changed?("c.xml")).to be false
    end

    it "follows an XML member to the AsciiDoc it is compiled from" do
      File.write(File.join(@dir, "b.adoc"), "= B changed\n")
      expect(change_set.changed?(File.join(@dir, "b.xml"))).to be true
    end

    it "counts committed and untracked changes" do
      File.write(File.join(@dir, "c.xml"), "<c>2</c>")
      git(@dir, "commit", "-q", "-am", "c")
      File.write(File.join(@dir, "parts/new.adoc"), "new\n")
      expect(change_set.changed?("c.xml")).to be true
      expect(change_set.paths).to include(
        File.join(File.realpath(@dir), "parts/new.adoc"),
      )
    end

    # Loose-leaf units (metanorma-cli#495): standoc reads the update
    # register into the document, so a register change alone counts.
    context "with update registers" do
      let(:root) { File.realpath(@dir) }

      def put(name, text)
        FileUtils.mkdir_p(File.dirname(File.join(root, name)))
        File.write(File.join(root, name), text)
      end

      before do
        put("part.adoc", "= Part\n:update-records: units/doc.yaml\n\n" \
                         "include::units/u1/en.adoc[]\n")
        put("units/u1/en.adoc", "[#U1,update-unit=U1," \
                                "update-records=\"units/u1/updates.yaml\"]\n")
        put("units/u1/updates.yaml", "U1: []\n")
        put("units/doc.yaml", "{}\n")
        put("other.adoc", "= Other\n:update-records: {regs}/x.yaml\n")
        git(root, "add", ".")
        git(root, "commit", "-q", "-m", "registers")
        git(root, "tag", "-f", "base")
      end

      it "counts a change in a register named on an included block" do
        put("units/u1/updates.yaml", "U1: [{}]\n")
        expect(change_set.changed?("part.adoc")).to be true
      end

      it "does not count a register path built from an attribute" do
        put("units/u1/updates.yaml", "U1: [{}]\n")
        expect(change_set.changed?("other.adoc")).to be false
      end

      it "counts a change in the register named by the document attribute" do
        put("units/doc.yaml", "U2: []\n")
        expect(change_set.changed?("part.adoc")).to be true
      end

      it "lists the registers among the member's sources" do
        expect(change_set.sources(File.join(root, "part.adoc"))).to include(
          File.join(root, "units/u1/updates.yaml"),
          File.join(root, "units/doc.yaml"),
        )
      end
    end

    it "raises on an unknown ref" do
      expect { described_class.new("nope", @dir) }
        .to raise_error(ArgumentError, /unknown git ref nope/)
    end

    it "builds nothing for a normal build" do
      expect(described_class.for(nil, @dir)).to be_nil
      cs = change_set
      expect(described_class.for(cs, @dir)).to be cs
    end
  end

  describe "rendering" do
    around do |ex|
      Dir.mktmpdir do |d|
        @dir = d
        ex.run
      end
    end

    before do
      manifest = File.read(File.join(fixtures, "collection_member_fail.yml"))
        .sub(/^  docref:.*\z/m, <<~YAML.gsub(/^/, "  "))
          docref:
            - fileref: dummy.xml
              identifier: ISO 44001
            - fileref: dummy.1.xml
              identifier: ISO 44002
        YAML
      repo(@dir, "collection.yml" => manifest,
                 "dummy.xml" => File.read(File.join(fixtures, "dummy.xml")),
                 "dummy.1.xml" => File.read(File.join(fixtures,
                                                      "dummy.1.xml")))
    end

    def render(**opts)
      Metanorma::Collection.parse(File.join(@dir, "collection.yml"))
        .render(format: %i[xml html], output_folder: out,
                compile: { install_fonts: false }, **opts)
    end

    def out
      File.join(@dir, "_site")
    end

    def mark(name)
      File.write(File.join(out, name), "KEPT")
    end

    def kept?(name)
      File.read(File.join(out, name)) == "KEPT"
    end

    it "rebuilds only the members changed since the ref" do
      render
      mark("dummy.html")
      mark("dummy.1.html")
      xml = File.join(@dir, "dummy.1.xml")
      File.write(xml, File.read(xml).sub("</title>", " amended</title>"))

      render(changed_since: "base")
      expect(kept?("dummy.html")).to be true
      expect(kept?("dummy.1.html")).to be false

      # the default build still renders every member
      render
      expect(kept?("dummy.html")).to be false
    end

    it "rebuilds an unchanged member whose output is missing" do
      render(changed_since: "base")
      expect(File.exist?(File.join(out, "dummy.html"))).to be true
      expect(File.exist?(File.join(out, "dummy.1.html"))).to be true
    end
  end
end
