# frozen_string_literal: true

require "spec_helper"

RSpec.describe Metanorma::Util::FontistHelper, :fontist do
  # Real Fontist behaviour, no stubbing: the manifest names a font that
  # is not installed on this machine, so the location lookup raises
  # Fontist::Errors::MissingFontError (--continue-without-fonts, #595).
  describe ".location_manifest" do
    let(:missing_font) { "Metanorma Spec Nonexistent Font QWERTZ" }
    let(:processor) { Struct.new(:fonts_manifest).new(nil) }
    let(:source_attributes) { { fonts: missing_font } }

    it "raises MissingFontError for a missing font without the flag" do
      expect do
        described_class.location_manifest(processor, source_attributes)
      end.to raise_error(Fontist::Errors::MissingFontError)
    end

    it "drops the missing font from the manifest with continue_without_fonts" do
      manifest = described_class.location_manifest(
        processor, source_attributes, continue_without_fonts: true,
      )
      expect(manifest).not_to include(missing_font)
    end
  end
end
