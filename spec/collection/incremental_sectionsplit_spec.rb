# frozen_string_literal: true

require_relative "../spec_helper"
require "fileutils"
require "tmpdir"

# GATING TEST for suma#94: does the incremental engine (preserve_unresolved +
# artifact_store_dir) survive a *sectionsplit* member? The real SRL collection is
# sectionsplit: true, so the staged per-process build must stage sectionsplit
# sub-collections. collection_sectionsplit_solo.yml is a single sectionsplit
# document whose cross-document reference to an absent sibling is otherwise
# stripped to an "Unresolved reference" message -- exactly the isolated-build case
# preserve mode exists to fix. This test asserts the engine (a) does not crash and
# (b) preserves + stores the stub instead of stripping it.
RSpec.describe "incremental build survives sectionsplit" do
  INPATH = "spec/fixtures/collection"

  around do |ex|
    Dir.mktmpdir { |d| @store = File.join(d, "cache"); ex.run }
  end

  it "preserves and stores a sectionsplit member's cross-doc stub without crashing" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
    of = File.join(FileUtils.pwd, "spec/fixtures/output")
    col = Metanorma::Collection.parse "#{INPATH}/collection_sectionsplit_solo.yml"

    expect do
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "collection_cover.html",
        compile: { install_fonts: false },
        preserve_unresolved: true,
        artifact_store_dir: @store,
      )
    end.not_to raise_error

    # (a) engine survived sectionsplit + preserve + store.
    # (b) did preserve+store actually engage for the sectionsplit member?
    semantics = Dir[File.join(@store, "*.semantic.xml")]
    expect(semantics).not_to be_empty
    # (c) the absent-sibling cross-doc ref is preserved as a stub (bibitemid kept),
    # not stripped to the "Unresolved reference" text a bare isolated build emits.
    stored = semantics.map { |f| File.read(f) }.join
    expect(stored).to include("bibitemid")

    FileUtils.rm_rf of
  end
end
