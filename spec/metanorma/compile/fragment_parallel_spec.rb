require "spec_helper"
require "fileutils"
require "tmpdir"

require "metanorma/compile/fragment_parallel"

# Fragment-based parallel semantic compilation (spike, metanorma#620):
# unit coverage for the source splitter and the semantic-XML stitcher.
# The full round trip (subprocess compiles) is exercised manually against
# the benchmark corpus; these specs pin the split and merge semantics.
RSpec.describe Metanorma::Compile::FragmentParallel do
  let(:dir) { Dir.mktmpdir("fragment-parallel-spec") }
  let(:workers) { 4 }

  let(:instance) do
    described_class.allocate.tap do |fp|
      fp.instance_variable_set(:@dir, dir)
      fp.instance_variable_set(:@workers, workers)
      fp.instance_variable_set(:@created, [])
      fp.instance_variable_set(:@prefix, ".test.frag")
    end
  end

  after { FileUtils.remove_entry(dir) }

  def segmentize(text)
    instance.send(:segmentize, text.split("\n"))
  end

  describe "#segmentize" do
    it "splits at top-level headings, keeping preamble separate" do
      header, segs = segmentize(<<~SRC)
        = Doc
        :mn-document-class: iso

        == Scope

        Body.

        == Terms and definitions

        Term body.
      SRC
      expect(header).to eq(["= Doc", ":mn-document-class: iso"])
      expect(segs.map { |s| s[:lines].grep(/\S/).first }).to eq(
        ["== Scope", "== Terms and definitions"],
      )
    end

    it "keeps attribute and anchor lines with the heading they style" do
      _header, segs = segmentize(<<~SRC)
        = Doc

        [[clause-1]]
        == Scope

        Body.

        [bibliography]
        == Normative references
      SRC
      expect(segs.map { |s| s[:lines].grep(/\S/).first })
        .to eq(["[[clause-1]]", "[bibliography]"])
      expect(segs[1][:lines].grep(/\S/)[1]).to eq("== Normative references")
    end

    it "gives inter-clause blank lines to the following fragment" do
      _header, segs = segmentize(<<~SRC)
        = Doc

        == Scope

        Body.

        == Terms and definitions

        Term body.
      SRC
      expect(segs[0][:lines].last).to eq("Body.")
      expect(segs[1][:lines]).to start_with(["", "== Terms and definitions"])
    end

    it "does not split on subclause headings" do
      _header, segs = segmentize(<<~SRC)
        = Doc

        == Terms and definitions

        === Terms related to EXPRESS

        Concept.
      SRC
      expect(segs.size).to eq(1)
      expect(segs[0][:lines].join("\n"))
        .to include("=== Terms related to EXPRESS")
    end

    it "keeps a style line followed by a frame title and heading together" do
      _header, segs = segmentize(<<~SRC)
        = Doc

        [[introduction]]
        .Introduction frame
        == Introduction

        Body.
      SRC
      expect(segs.size).to eq(1)
      expect(segs[0][:lines].grep(/\S/).first).to eq("[[introduction]]")
      expect(segs[0][:lines].grep(/\S/)[1]).to eq(".Introduction frame")
    end
  end

  describe "#data2text_mega and #mega_fragments" do
    let(:groups_yaml) do
      (1..10).map { |i| { "title" => "Group #{i}", "name" => "g#{i}" } }
    end

    let(:segment) do
      { lines: <<~SRC.split("\n") }
        == Terms and definitions

        [yaml2text,groups.yaml,groups]
        ------
        {% for group in groups %}
        === {{ group.title }}
        ------
      SRC
    end

    before do
      File.write(File.join(dir, "groups.yaml"), YAML.dump(groups_yaml))
    end

    it "detects an array-valued yaml2text block" do
      mega = instance.send(:data2text_mega, segment)
      expect(mega).not_to be_nil
      expect(mega[:entries].size).to eq(10)
      expect(mega[:var]).to eq("groups")
    end

    it "does not split single-entry data" do
      File.write(File.join(dir, "groups.yaml"), YAML.dump(groups_yaml[0, 1]))
      expect(instance.send(:data2text_mega, segment)).to be_nil
    end

    it "emits chunk fragments carrying heading chain and template verbatim" do
      fragments = []
      header = ["= Doc", ":attr: x"]
      instance.send(:mega_fragments, fragments, header, segment,
                    instance.send(:data2text_mega, segment))
      # chunk count is capped at the worker count and never exceeds the
      # entry count: 10 entries with 4 workers yield 4 chunks of 2-3
      expect(fragments.size).to eq(4)
      src = File.read(fragments.first[:path])
      expect(src).to start_with("= Doc\n:attr: x\n== Terms and definitions")
      expect(src).to include("[yaml2text,.test.frag-0.data.yaml,groups]")
      expect(src).to include("=== {{ group.title }}")
      data = YAML.load_file(File.join(dir, ".test.frag-0.data.yaml"))
      expect(data).to be_an(Array)
      expect(data.size).to eq(3)
    end
  end

  describe "#stitch (via #stitch_fragment_root and #reorder_root)" do
    NS = "https://www.metanorma.org/ns/standoc".freeze

    let(:base_xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
        <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata><metanorma-extension><semantic-metadata><stage-published>false</stage-published></semantic-metadata>
        </metanorma-extension>
        <boilerplate><clause anchor="boilerplate-x"><title>X</title></clause></boilerplate><preface><foreword id="_f1"><p>Foreword.</p></foreword></preface><sections><clause anchor="clause-1" type="scope"><title>Scope</title><p>Body.</p>
        </clause>
        </sections>
        </metanorma>
      XML
    end

    def stitch(base, frag)
      inst = described_class.allocate.tap do |fp|
        fp.instance_variable_set(:@dir, dir)
      end
      b = Nokogiri::XML(base, &:huge)
      inst.send(:stitch_fragment_root, b,
                Nokogiri::XML(frag, &:huge), NS)
      inst.send(:reorder_root, b)
      b
    end

    it "appends an annex after sections and keeps layout" do
      frag = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
        <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata><metanorma-extension><semantic-metadata><stage-published>false</stage-published></semantic-metadata>
        </metanorma-extension>
        <boilerplate><clause anchor="boilerplate-x"><title>X</title></clause></boilerplate><preface><foreword id="_f2"><p>Generated.</p></foreword></preface><sections><clause anchor="clause-1" type="scope"><title>Scope</title><p>Body.</p>
        </clause>
        </sections><annex anchor="annex-a"><title>Annex</title></annex>
        </metanorma>
      XML
      out = stitch(base_xml, frag)
      names = out.root.children.select(&:element?).map(&:name)
      expect(names).to eq(%w[bibdata metanorma-extension boilerplate preface
                             sections annex])
    end

    it "drops the generated foreword of later fragments and keeps annexes" do
      frag = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
        <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata><metanorma-extension><semantic-metadata><stage-published>false</stage-published></semantic-metadata>
        </metanorma-extension>
        <boilerplate><clause anchor="boilerplate-x"><title>X</title></clause></boilerplate><preface><foreword id="_gen"><p>Generated.</p></foreword></preface><sections><clause anchor="clause-1" type="scope"><title>Scope</title><p>Body.</p>
        </clause>
        </sections><annex anchor="annex-a"><title>Annex</title></annex><bibliography><bibitem anchor="REF-1"><docidentifier>REF 1</docidentifier></bibitem></bibliography>
        </metanorma>
      XML
      out = stitch(base_xml, frag)
      preface = out.root.at_xpath("./xmlns:preface", xmlns: NS)
      expect(preface.xpath("./xmlns:foreword", xmlns: NS).size).to eq(1)
      biblio = out.root.at_xpath("./xmlns:bibliography", xmlns: NS)
      expect(biblio.at_xpath("./xmlns:bibitem", xmlns: NS)["anchor"])
        .to eq("REF-1")
      names = out.root.children.select(&:element?).map(&:name)
      expect(names).to eq(%w[bibdata metanorma-extension boilerplate preface
                             sections annex bibliography])
    end

    it "unifies wrapper clauses by title and merges their children" do
      frag = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
        <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata>
        <sections><clause anchor="clause-1" type="scope"><title>Scope</title><p>Body.</p>
        </clause><terms obligation="normative"><title>Terms and definitions</title><term anchor="term-A"><preferred><expression><name>A</name></expression></preferred></term>
        </terms></sections>
        </metanorma>
      XML
      out = stitch(base_xml, frag)
      sections = out.root.at_xpath("./xmlns:sections", xmlns: NS)
      terms = sections.xpath("./xmlns:terms", xmlns: NS)
      expect(terms.size).to eq(1)
      expect(terms.xpath("./xmlns:term", xmlns: NS).size).to eq(1)
    end

    it "does not merge distinct annexes" do
      one = stitch(base_xml, <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
        <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata>
        <annex anchor="annex-a"><title>Annex A</title></annex>
        </metanorma>
      XML
      inst = described_class.allocate.tap do |fp|
        fp.instance_variable_set(:@dir, dir)
      end
      inst.send(:stitch_fragment_root,
                one, Nokogiri::XML(<<~XML, &:huge), NS)
        <?xml version="1.0" encoding="UTF-8"?>
        <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
        <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata>
        <annex anchor="annex-b"><title>Annex B</title></annex>
        </metanorma>
      XML
      inst.send(:reorder_root, one)
      annexes = one.root.xpath("./xmlns:annex", xmlns: NS)
      expect(annexes.map { |a| a["anchor"] }).to eq(%w[annex-a annex-b])
    end
  end

  describe "forked-worker compilation" do
    let(:workers) { 2 }

    let(:klass) do
      Class.new(described_class) do
        # The scheduler, forking, log capture and stitching run for real;
        # only the per-fragment metanorma compile is replaced, by
        # inheritance, with a write of a minimal fragment XML.
        def compile_fragment(f)
          anchor = File.basename(f[:path], ".adoc")
          File.write(f[:path].sub(/\.adoc$/, ".xml"), <<~XML)
            <?xml version="1.0" encoding="UTF-8"?>
            <metanorma xmlns="#{NS}" type="semantic" flavor="iso">
            <bibdata type="standard"><docidentifier>ISO 1</docidentifier></bibdata>
            <sections><clause anchor="#{anchor}"><title>T</title></clause></sections>
            </metanorma>
          XML
        end
      end
    end

    let(:docfile) do
      path = File.join(dir, "document.adoc")
      File.write(path, <<~SRC)
        = Doc
        :mn-document-class: iso

        == Scope

        Alpha.

        == Terms and definitions

        Beta.
      SRC
      path
    end

    it "compiles every fragment in a forked worker and stitches the result" do
      xml = klass.new(docfile, {}, workers).run
      out = Nokogiri::XML(xml, &:huge)
      clauses = out.root.xpath(".//xmlns:clause", xmlns: NS)
      expect(clauses.map { |c| c["anchor"] })
        .to contain_exactly(".document.frag-0", ".document.frag-1")
    end

    it "reports a fragment whose child exits nonzero" do
      failing = Class.new(described_class) do
        def compile_fragment(_f)
          warn "child boom"
          raise "child boom"
        end
      end
      expect { failing.new(docfile, {}, workers).run }
        .to raise_error(/fragment compile failed/)
    end

    it "records each child's output in its fragment log" do
      logging = Class.new(described_class) do
        def compile_fragment(f)
          warn "logged from #{File.basename(f[:path])}"
          File.write(f[:path].sub(/\.adoc$/, ".xml"),
                     "<metanorma xmlns=\"#{NS}\" type=\"semantic\"/>")
        end
      end
      ENV["METANORMA_PARALLEL_KEEP"] = "1"
      logging.new(docfile, {}, workers).run
      logs = Dir.glob("#{dir}/.document.frag-*.adoc.log")
      expect(logs.size).to eq(2)
      logs.each do |log|
        expect(File.read(log))
          .to include("logged from #{File.basename(log, '.log')}")
      end
    ensure
      ENV.delete("METANORMA_PARALLEL_KEEP")
    end
  end

  describe "glossarist dataset preload" do
    let(:klass) do
      Class.new(described_class) do
        def compile_fragment(f)
          File.write(f[:path].sub(/\.adoc$/, ".xml"),
                     "<metanorma xmlns=\"#{NS}\" type=\"semantic\"/>")
        end
      end
    end

    let(:fixture) do
      File.expand_path("fixtures/dataset-glossarist-v2", __dir__)
    end

    let(:docfile_with_dataset) do
      FileUtils.cp_r(fixture, File.join(dir, "dataset-v2"))
      path = File.join(dir, "document.adoc")
      File.write(path, <<~SRC)
        = Doc
        :mn-document-class: iso
        :glossarist-dataset: ds:dataset-v2

        == Terms and definitions
      SRC
      path
    end

    after do
      ENV.delete(Metanorma::Compile::FragmentParallel::SHARED_DATASETS_ENV)
      if defined?(Metanorma::Plugin::Glossarist::DatasetRegistry) &&
         Metanorma::Plugin::Glossarist::DatasetRegistry
         .respond_to?(:clear_shared_stores)
        Metanorma::Plugin::Glossarist::DatasetRegistry.clear_shared_stores
      end
    end

    let(:plugin) do
      require "metanorma-plugin-glossarist"
      Metanorma::Plugin::Glossarist::DatasetRegistry
    end

    it "leaves the store gate alone when the plugin predates sharing" do
      skip "plugin carries the shared store cache" unless
        plugin.respond_to?(:shared_store_for)

      klass.new(docfile_with_dataset, {}, 2).run
      expect(ENV[Metanorma::Compile::FragmentParallel::SHARED_DATASETS_ENV])
        .to eq("1")
      # workers are forked from fragments under the real-pathed docdir,
      # so their registry lookups key on the real path
      entry = plugin.shared_store_for(
        File.realpath(File.join(dir, "dataset-v2")),
      ) { raise "dataset was not preloaded by the parent" }
      expect(entry.concepts.map(&:id).size).to eq(4)
    end

    it "skips the preload when the plugin lacks the shared store" do
      klass.new(docfile_with_dataset, {}, 2).run
      if plugin.respond_to?(:shared_store_for)
        expect(ENV[Metanorma::Compile::FragmentParallel::SHARED_DATASETS_ENV])
          .to eq("1")
      else
        expect(ENV[Metanorma::Compile::FragmentParallel::SHARED_DATASETS_ENV])
          .to be_nil
      end
    end

    it "honours an explicit shared-store opt-out" do
      skip "plugin carries the shared store cache" unless
        plugin.respond_to?(:shared_store_for)

      ENV[Metanorma::Compile::FragmentParallel::SHARED_DATASETS_ENV] = "0"
      klass.new(docfile_with_dataset, {}, 2).run

      expect(ENV[Metanorma::Compile::FragmentParallel::SHARED_DATASETS_ENV])
        .to eq("0")
      # the gate is off, so nothing may have been preloaded
      expect(plugin.shared_store_for(
        File.realpath(File.join(dir, "dataset-v2")),
      ) { raise "unexpected load under a disabled gate" }).to be_nil
    end
  end
end
