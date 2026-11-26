require_relative "../spec_helper"

# A member's :outputs is read by the other members of the render pool
# (metanorma#705) while they resolve their citations to it: update_bibitem ->
# FileLookup#url -> ref_file. ref_file takes :outputs[:html] when it is
# there, converts the .xml out_path to .html when :outputs is absent, and
# keeps the raw .xml out_path when :outputs exists without :html. So a member
# must never expose a partly filled :outputs hash: a citation resolved in
# that window links to document.N.xml, which is not in the output.
RSpec.describe Metanorma::Collection::Renderer do
  let(:renderer) { described_class.allocate }
  let(:outdir) { "/build/_site" }
  let(:entry) do
    { type: "fileref", rel_path: "document.35.adoc",
      out_path: "document.35.xml" }
  end
  let(:lookup) do
    Metanorma::Collection::FileLookup.allocate.tap do |l|
      l.instance_variable_set(:@parent,
                              instance_double(described_class,
                                              outdir: outdir))
    end
  end
  let(:files) do
    instance_double(Metanorma::Collection::FileLookup).tap do |f|
      allow(f).to receive(:get) { |_id, key| entry[key] }
      allow(f).to receive(:set) { |_id, key, value| entry[key] = value }
      allow(f).to receive(:preserve_directory_structure?).and_return(nil)
    end
  end
  let(:formats) do
    { xml: "xml", html: "html", presentation: "presentation.xml" }
  end

  # the citation URL another pool worker would write for this member now
  def citation_url_now
    lookup.targetfile(entry, relative: true, doc: true)[1]
  end

  # compile the member; return the citation URL as seen at each format step
  def citation_urls_while_registering
    seen = []
    allow(renderer).to receive(:file_compile_format)
      .and_wrap_original do |original, *args, **kwargs|
        seen << citation_url_now
        original.call(*args, **kwargs)
      end
    renderer.file_compile("document.35.xml", "document.35.xml", "doc35", 1)
    seen
  end

  before do
    renderer.instance_variable_set(:@files, files)
    renderer.instance_variable_set(:@outdir, outdir)
    allow(renderer).to receive_messages(
      compile_options_base: { extension_keys: %i[xml presentation html] },
      compile_options_update: {}, compile_options_bare_after_first: {},
      member_compile: instance_double(Metanorma::Compile, errors: []),
      member_processor: instance_double(Metanorma::Processor,
                                        output_formats: formats),
      file_compile_verify: nil, concatenate_presentation?: false
    )
  end

  it "resolves citations to a member as .html while it registers its " \
     "outputs" do
    expect(citation_urls_while_registering).to eq ["document.35.html"] * 3
  end

  it "publishes the member's outputs complete, with :html" do
    renderer.file_compile("document.35.xml", "document.35.xml", "doc35", 1)
    expect(entry[:outputs].keys).to eq %i[xml presentation html]
    expect(citation_url_now).to eq "document.35.html"
  end
end
