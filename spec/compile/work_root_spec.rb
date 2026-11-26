require_relative "../spec_helper"
require "fileutils"
require "digest"
require "tmpdir"

RSpec.describe Metanorma::Compile do
  # The compile driver owns the work root hosting the output converters'
  # shared asset store and scratch directories (isodoc#920): it is keyed
  # by the document's semantic XML — identical documents reuse the
  # identical root, parallel documents never collide — and is removed at
  # build end unless keep_workdir is set.
  let(:compile) { described_class.new }
  let(:semantic_xml) { "<iso-standard/>" }

  def derived_root(xml)
    File.join(Dir.tmpdir, "metanorma",
              "work-#{Digest::SHA256.hexdigest(xml.to_s)}")
  end

  describe "#init_work_root" do
    it "creates a deterministic root keyed by the semantic XML" do
      options = {}
      root = compile.init_work_root(semantic_xml, options)
      expect(root).to eq(derived_root(semantic_xml))
      expect(Dir.exist?(root)).to be(true)
      expect(options[:workdir]).to eq(root)
    ensure
      FileUtils.rm_rf(root)
    end

    it "reuses the same root for identical documents" do
      expect(compile.init_work_root(semantic_xml, {}))
        .to eq(compile.init_work_root(semantic_xml.dup, {}))
    ensure
      FileUtils.rm_rf(derived_root(semantic_xml))
    end

    it "derives distinct roots for distinct documents" do
      other = "<iso-standard version='2'/>"
      compile.init_work_root(semantic_xml, {})
      compile.init_work_root(other, {})
      expect(derived_root(semantic_xml)).not_to eq(derived_root(other))
    ensure
      FileUtils.rm_rf(derived_root(semantic_xml))
      FileUtils.rm_rf(derived_root(other))
    end

    it "honors an explicit work_dir override" do
      Dir.mktmpdir("mn-work") do |override|
        root = compile.init_work_root(semantic_xml, work_dir: override)
        expect(root).to eq(override)
        expect(Dir.exist?(override)).to be(true)
      end
    end
  end

  describe "#teardown_work_root" do
    it "removes the work root after the build" do
      root = compile.init_work_root(semantic_xml, {})
      compile.teardown_work_root({})
      expect(Dir.exist?(root)).to be(false)
    end

    it "keeps the work root under keep_workdir" do
      root = compile.init_work_root(semantic_xml, {})
      compile.teardown_work_root(keep_workdir: true)
      expect(Dir.exist?(root)).to be(true)
    ensure
      FileUtils.rm_rf(root)
    end

    it "is a no-op before a work root was created" do
      expect { compile.teardown_work_root({}) }.not_to raise_error
    end
  end
end
