# frozen_string_literal: true

require_relative "../../../spec_helper"

# The suffix-swap helpers re-key ids of stored documents from the suffix
# they were stored under to the rendering build's own suffix (the
# reinflated sectionsplit path). They mirror the append-only machinery of
# add_document_suffix: same coverage, replacing the suffix instead.
RSpec.describe Metanorma::Collection::Util do
  describe ".swap_suffix_value" do
    it "re-keys a suffixed value to the new suffix" do
      expect(described_class.swap_suffix_value("annex_old", "old", "new"))
        .to eq("annex_new")
    end

    it "appends the new suffix to a value carrying no suffix" do
      expect(described_class.swap_suffix_value("annex", "old", "new"))
        .to eq("annex_new")
    end

    it "leaves a value already keyed by the new suffix" do
      expect(described_class.swap_suffix_value("annex_new", "old", "new"))
        .to eq("annex_new")
    end
  end

  describe ".swap_ids_css_string" do
    def swap(style)
      described_class.swap_ids_css_string(style, ["fig1"], "old", "new")
    end

    it "re-keys url(#id) references" do
      expect(swap("fill: url(#fig1_old)")).to eq("fill: url(#fig1_new)")
    end

    it "re-keys [id='…'] selectors" do
      expect(swap("[id='fig1_old'] { fill: red }"))
        .to eq("[id='fig1_new'] { fill: red }")
    end

    it "re-keys bare id attribute values" do
      expect(swap("fig1_old")).to eq("fig1_new")
    end

    it "leaves ids keyed by other suffixes" do
      expect(swap("fill: url(#fig1_other)"))
        .to eq("fill: url(#fig1_other)")
    end

    it "leaves ids that merely contain the suffixed id" do
      expect(swap("fill: url(#xfig1_old)"))
        .to eq("fill: url(#xfig1_old)")
    end
  end
end
