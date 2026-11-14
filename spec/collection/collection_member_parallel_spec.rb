# frozen_string_literal: true

require_relative "../spec_helper"

COLLECTION_INPATH = "spec/fixtures/collection"
COLLECTION_OUTPATH = "spec/fixtures/output"

RSpec.describe Metanorma::Collection do
  # Collection members render on a bounded pool (metanorma#705). Two members
  # of this collection fail to compile: they request an output format the
  # flavor does not support, which pools a compile error against that
  # member's own Compile instance. The members compile concurrently with the
  # successful one, so each failure must surface for its own member alone,
  # in manifest order, and the surviving member's outputs must exist.
  it "renders all members under a member pool, attributing each member's " \
     "compile failures to that member (#705)" do
    file = "#{COLLECTION_INPATH}/collection_member_fail.yml"
    of = File.join(FileUtils.pwd, COLLECTION_OUTPATH)
    col = Metanorma::Collection.parse file
    err = nil
    begin
      col.render(
        format: %i[presentation xml html],
        output_folder: of,
        compile: { install_fonts: false },
        member_pool_size: 2,
      )
    rescue Metanorma::RenderFailureException => e
      err = e
    end
    expect(err).not_to be_nil
    # every failed member is reported, attributed to its own identifier ...
    expect(err.message)
      .to include("Failed to render collection member ISO 44002")
    expect(err.message)
      .to include("Failed to render collection member ISO 44003")
    expect(err.message)
      .to include("bogus format is not supported for this standard.")
    # ... and none is attributed to the member that rendered successfully
    expect(err.message).not_to include("ISO 44001")
    # failures are reported in manifest order, not completion order
    expect(err.message.index("ISO 44002"))
      .to be < err.message.index("ISO 44003")
    # the successful member's outputs exist
    expect(File.exist?("#{COLLECTION_OUTPATH}/dummy.html")).to be true
    expect(File.exist?("#{COLLECTION_OUTPATH}/dummy.xml")).to be true
    # the failing members still produced the formats they support
    expect(File.exist?("#{COLLECTION_OUTPATH}/dummy.1.xml")).to be true
    expect(File.exist?("#{COLLECTION_OUTPATH}/dummy.2.xml")).to be true
    # the unsupported format produced neither output nor registration
    expect(File.exist?("#{COLLECTION_OUTPATH}/dummy.1.html")).to be false
    FileUtils.rm_rf of
  end

  # Member render order must not leak into the output: the same collection
  # rendered under different pool widths -- and so different completion
  # interleavings -- produces identical member documents. Anchor ids that
  # carry a randomly generated UUID (unlabelled note/example anchors, a
  # per-render value even on sequential builds) are normalised away; every
  # other byte must match.
  it "renders identical member outputs regardless of pool width (#705)" do
    file = "#{COLLECTION_INPATH}/collection.dup.yml"
    of1 = File.join(FileUtils.pwd, "#{COLLECTION_OUTPATH}_pool2")
    of2 = File.join(FileUtils.pwd, "#{COLLECTION_OUTPATH}_pool3")
    Metanorma::Collection.parse(file).render(
      format: %i[presentation xml html],
      output_folder: of1,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
      member_pool_size: 2,
    )
    Metanorma::Collection.parse(file).render(
      format: %i[presentation xml html],
      output_folder: of2,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
      member_pool_size: 3,
    )
    %w[dummy.html dummy.1.html dummy.2.html
       dummy.xml dummy.1.xml dummy.2.xml].each do |f|
      expect(File.exist?(File.join(of1, f))).to be true
      expect(normalise_uuids(File.read(File.join(of1, f), encoding: "UTF-8")))
        .to eq(normalise_uuids(File.read(File.join(of2, f), encoding: "UTF-8")))
    end
    FileUtils.rm_rf [of1, of2]
  end

  def normalise_uuids(content)
    content.gsub(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "_"
    )
  end
end
