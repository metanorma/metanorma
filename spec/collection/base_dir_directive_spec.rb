# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"
require "yaml"

# The `base-dir: collection` directive (metanorma#627): member compiles
# anchor their include jail at the collection directory instead of the
# process working directory, so a member include reaching above the
# member directory (../../../templates) resolves from any working
# directory. Without the directive the working-directory jail recovers
# the escaped include and loses it, as before.
RSpec.describe "collection base-dir directive" do
  FIXTURE = File.expand_path("../fixtures/collection/base_dir_propagation", __dir__)

  def compile_collection(dir, out)
    Metanorma::Collection.parse(File.join(dir, "collection.yml"))
      .render(format: [:xml], output_folder: out)
  end

  def member_xml(out)
    Dir[File.join(out, "**", "99001*.xml")].first ||
      Dir[File.join(out, "**", "*.xml")].reject { |f| f.include?("html") }.first
  end

  it "resolves an include above the member directory from a foreign working directory" do
    Dir.mktmpdir do |tmp|
      coll = File.join(tmp, "collection")
      FileUtils.cp_r(FIXTURE, coll)
      out = File.join(tmp, "site")
      elsewhere = File.join(tmp, "elsewhere")
      FileUtils.mkdir_p(elsewhere)
      Dir.chdir(elsewhere) do
        compile_collection(coll, out)
      end
      xml = File.read(member_xml(out), encoding: "utf-8")
      expect(xml).to include("Shared template content lives above the member directory.")
      expect(xml).not_to include("Unresolved directive")
    end
  end

  it "keeps the working-directory jail when the directive is absent" do
    Dir.mktmpdir do |tmp|
      coll = File.join(tmp, "collection")
      FileUtils.cp_r(FIXTURE, coll)
      yaml = File.read(File.join(coll, "collection.yml"))
        .sub(/  - base-dir: collection\n/, "")
      File.write(File.join(coll, "collection.yml"), yaml)
      out = File.join(tmp, "site")
      elsewhere = File.join(tmp, "elsewhere")
      FileUtils.mkdir_p(elsewhere)
      # Today's behavior, pinned: from a foreign working directory the
      # escaped include leaves the jail and the member compile FATALs
      # (metanorma aborts).
      Dir.chdir(elsewhere) do
        expect { compile_collection(coll, out) }.to raise_error(SystemExit)
      end
    end
  end
end
