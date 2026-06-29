require_relative "../spec_helper"

# Regression for https://github.com/metanorma/iso-10303/issues/208
#
# Under sectionsplit, a document's section files are emitted at the sectionsplit
# output location (the collection root, or the directory of a configured
# sectionsplit_filename), NOT at the document's own out_path. An attachment /
# citation URL must therefore be relativised against that split location. If it
# is relativised against the (unsplit) document out_path instead, the ../../
# climbs above the split file and the attachment link breaks.
#
# referencing_html_location supplies the base path that update_bibitem_prep
# hands to make_relative_path, so these two together pin the resulting URL.
RSpec.describe Metanorma::Collection::Renderer do
  subject(:renderer) { described_class.allocate }

  # out_path is in a subdirectory (as in iso-10303's documents/<part>/...),
  # which is the only situation where sectionsplit relocation changes the depth.
  def stub_files(sectionsplit:, preserve: nil, outputs: nil,
                 out_path: "documents/event/document.xml")
    attrs = { sectionsplit: sectionsplit, outputs: outputs, out_path: out_path }
    files = double("FileLookup")
    allow(files).to receive(:get) { |_id, key| attrs[key] }
    allow(files).to receive(:preserve_directory_structure?).and_return(preserve)
    renderer.instance_variable_set(:@files, files)
  end

  # the attachment URL as resolved onto the referencing document's pages
  def resolved_url(attachment)
    base = renderer.send(:referencing_html_location, "doc", attachment)
    renderer.send(:make_relative_path, base, "plain_schemas/x.exp")
  end

  describe "#referencing_html_location" do
    it "relativises an attachment of a sectionsplit document against the " \
       "collection root (no ../../ overshoot)" do
      stub_files(sectionsplit: true)
      expect(resolved_url(true)).to eq "plain_schemas/x.exp"
    end

    it "relativises against the sectionsplit subdirectory when one is set" do
      stub_files(sectionsplit: true, preserve: "split/{basename}.html")
      expect(resolved_url(true)).to eq "../plain_schemas/x.exp"
    end

    it "uses the document's own out_path when it is not sectionsplit" do
      stub_files(sectionsplit: false)
      expect(resolved_url(true)).to eq "../../plain_schemas/x.exp"
    end

    it "leaves non-attachment targets on the document out_path even under " \
       "sectionsplit" do
      stub_files(sectionsplit: true)
      expect(resolved_url(false)).to eq "../../plain_schemas/x.exp"
    end
  end
end
