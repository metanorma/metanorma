require_relative "spec_helper"
require "fileutils"

require "fontist"

RSpec.describe Metanorma::Compile do
  def clean_outputs
    %w(xml presentation.xml html alt.html doc relaton.xml err rxl pdf).each do |ext|
      FileUtils.rm_f Dir["spec/assets/*.#{ext}"]
    end

    FileUtils.rm_rf "spec/assets/test"
    FileUtils.rm_rf "spec/assets/extract"
  end

  before(:each) { clean_outputs }
  after(:all) { clean_outputs }

  around(:each) do |example|
    begin
      example.run
    rescue SystemExit
      fail "Unexpected exit encountered"
    end
  end

  it "passes asciidoc options onto isodoc" do
    mock_iso_processor_output("spec/assets/test2.xml", "spec/assets/test2.presentation.xml",
                             {:datauriimage=>true, :sourcefilename=>"spec/assets/test2.adoc"})
    Metanorma::Compile.new.compile("spec/assets/test2.adoc", type: "iso", extension_keys: [:presentation],
                                  datauriimage: true, agree_to_terms: true)
  end

  it "fontist_install called" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install) {}
    expect(compile).to receive(:fontist_install).once
    expect(compile).to receive(:fontist_font_locations).once

    compile.compile("spec/assets/test.adoc", type: "iso", agree_to_terms: true)
  end

  it "fontist_install called with explicit no_install_fonts=false" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install) {}
    expect(compile).to receive(:fontist_install).once
    expect(compile).to receive(:fontist_font_locations).once

    compile.compile("spec/assets/test.adoc", type: "iso", agree_to_terms: true, no_install_fonts: false)
  end

  it "skip font install with no_install_fonts" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install) {}
    expect(compile).not_to receive(:fontist_install)

    compile.compile("spec/assets/test.adoc", type: "iso", no_install_fonts: true)
  end

  it "exit on license error" do
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install).and_raise(Fontist::Errors::LicensingError)

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "skip license error" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install).and_raise(Fontist::Errors::LicensingError)
    expect(compile).to receive(:fontist_install).once

    compile.compile("spec/assets/test.adoc", type: "iso", continue_without_fonts: true)
  end

  it "exit on license error" do
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install).and_raise(Fontist::Errors::LicensingError)
    expect(compile).to receive(:fontist_install).once

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "exit on missing fonts" do
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install).and_raise(
      Fontist::Errors::FontError.new("Font 'SomeFont' not found")
    )
    expect(compile).to receive(:fontist_install).once

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "handle on missing fonts" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install).and_raise(
      Fontist::Errors::FontError.new("Font 'SomeFont' not found")
    )
    expect(compile).to receive(:fontist_install).once

    compile.compile("spec/assets/test.adoc", type: "iso", continue_without_fonts: true)
  end

  it "handle missing fontist index" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    @fontist_install_called = 0
    allow(compile).to receive(:fontist_install) do
      @fontist_install_called += 1
      raise Fontist::Errors::FormulaIndexNotFoundError if @fontist_install_called == 1
    end
    allow(Fontist::Formula).to receive(:update_formulas_repo)
    expect(compile).to receive(:fontist_install).twice

    compile.compile("spec/assets/test.adoc", type: "iso", continue_without_fonts: true)
  end

  it "exit on twice missing fontist index" do
    compile = Metanorma::Compile.new

    allow(compile).to receive(:fontist_install).and_raise(Fontist::Errors::FormulaIndexNotFoundError)

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "exit on not supported font after missing fontist index" do
    compile = Metanorma::Compile.new

    @fontist_install_called = 0
    allow(compile).to receive(:fontist_install) do
      @fontist_install_called += 1
      raise Fontist::Errors::FormulaIndexNotFoundError if @fontist_install_called == 1
      raise Fontist::Errors::UnsupportedFontError.new("TestFont") if @fontist_install_called == 2
    end
    allow(Fontist::Formula).to receive(:update_formulas_repo)
    expect(compile).to receive(:fontist_install).twice

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "handle not supported font after missing fontist index" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    @fontist_install_called = 0
    allow(compile).to receive(:fontist_install) do
      @fontist_install_called += 1
      raise Fontist::Errors::FormulaIndexNotFoundError if @fontist_install_called == 1
      raise Fontist::Errors::UnsupportedFontError.new("TestFont") if @fontist_install_called == 2
    end
    allow(Fontist::Formula).to receive(:update_formulas_repo)
    allow(Fontist::Manifest::Locations).to receive(:from_hash)
    expect(compile).to receive(:fontist_install).twice

    compile.compile("spec/assets/test.adoc", type: "iso", continue_without_fonts: true)
  end

  it "handle no_progress" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    expect(compile).to receive(:fontist_install).with(anything, false, true)
    expect(compile).to receive(:fontist_font_locations).once

    compile.compile("spec/assets/test.adoc", type: "iso", no_progress: true)
  end

  it "processes metanorma options inside Asciidoc" do
    Metanorma::Compile.new.compile("spec/assets/test1.adoc", agree_to_terms: true)
    expect(File.exist?("spec/assets/test1.xml")).to be true
    expect(File.exist?("spec/assets/test1.doc")).to be false
    expect(File.exist?("spec/assets/test1.html")).to be true
    expect(File.exist?("spec/assets/test1.alt.html")).to be false
    expect(File.exist?("spec/assets/test1.relaton.xml")).to be true
    xml = File.read("spec/assets/test1.xml", encoding: "utf-8")
    expect(xml).to include "</iso-standard>"
  end

  it "processes an asciidoc ISO document" do
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/assets/test.adoc", type: "iso", agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be true
    expect(File.exist?("spec/assets/test.alt.html")).to be true
  end

  it "processes all extensions of an asciidoc ISO document" do
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/assets/test.adoc", type: "iso", extension_keys: [:all], agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be true
    expect(File.exist?("spec/assets/test.alt.html")).to be true
  end

  it "processes specific extensions of an asciidoc ISO document" do
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   extension_keys: %i(xml doc),
                                   agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be false
    expect(File.exist?("spec/assets/test.alt.html")).to be false
    xml = File.read("spec/assets/test.xml", encoding: "utf-8")
    expect(xml).to include "</iso-standard>"
  end

  it "write documents to specified output dir" do
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/examples/metanorma-collection/dummy.adoc",
                                   output_dir: "spec/assets",
                                   agree_to_terms: true)
    expect(File.exist?("spec/assets/dummy.doc"))
    expect(File.exist?("spec/assets/dummy.html"))
    expect(File.exist?("spec/assets/dummy.pdf"))
    expect(File.exist?("spec/assets/dummy.rxl"))
    expect(File.exist?("spec/assets/dummy.xml"))
    expect(File.exist?("spec/assets/dummy.alt.xml"))
    expect(File.exist?("spec/assets/dummy.presentation.xml"))
    expect(File.exist?("spec/assets/dummy.err"))
    Dir["spec/assets/dummy.*"].each { |f| File.delete f }
  end

  it "processes a Metanorma XML ISO document" do
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/assets/test.adoc", type: "iso", agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    FileUtils.rm_f %w(spec/assets/test.html spec/assets/test.alt.html spec/assets/test.doc)
    expect do
      Metanorma::Compile.new.compile("spec/assets/test.xml")
    end.not_to output(/Error: Please specify a standard type/).to_stdout
    expect(File.exist?("spec/assets/test.html")).to be true
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "ISO copyright office"
  end

  it "extracts isodoc options from asciidoc file" do
    Metanorma::Compile.new.compile("spec/assets/test.adoc", type: "iso", extension_keys: [:html], agree_to_terms: true)
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "font-family: body-font;"
    expect(html).to include "font-family: header-font;"
    expect(html).to include "font-family: monospace-font;"
  end

  it "wraps HTML output" do
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      wrapper: true,
      extension_keys: [:html],
      agree_to_terms: true
    )
    expect(File.exist?("spec/assets/test/test.html")).to be true
  end

  it "data64 encodes images" do
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      datauriimage: true,
      extension_keys: [:html],
      agree_to_terms: true
    )
    expect(File.exist?("spec/assets/test.html")).to be true
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "data:image"
  end

  it "exports bibdata" do
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      relaton: "spec/assets/testrelaton.xml",
      extension_keys: [:xml],
      agree_to_terms: true
    )
    expect(File.exist?("spec/assets/testrelaton.xml")).to be true
    xml = File.read("spec/assets/testrelaton.xml", encoding: "utf-8")
    expect(xml).to include %(<bibdata type="standard">)
  end

  it "exports bibdata, rxl" do
    Metanorma::Compile.new.compile("spec/assets/test.adoc", type: "iso", extension_keys: [:rxl], agree_to_terms: true)
    expect(File.exist?("spec/assets/test.rxl")).to be true
    xml = File.read("spec/assets/test.rxl", encoding: "utf-8")
    expect(xml).to include %(<bibdata type="standard">)
  end

  it "keeps asciimath" do
    Metanorma::Compile.new.compile("spec/assets/test1.adoc", type: "iso", extension_keys: [:xml], agree_to_terms: true)
    expect(File.exist?("spec/assets/test1.xml")).to be true
    xml = File.read("spec/assets/test1.xml", encoding: "utf-8")
    expect(xml).not_to include %(<stem type="MathML">)
    expect(xml).to include %(<stem type="AsciiMath">)
  end

  it "exports assets" do
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      extract: "spec/assets/extract",
      extract_type: %i(sourcecode image requirement),
      extension_keys: %i(xml html),
      agree_to_terms: true
    )
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/extract/sourcecode/sourcecode-0000.txt")).to be true
    expect(File.exist?("spec/assets/extract/sourcecode/sourcecode-0001.txt")).to be false
    expect(File.exist?("spec/assets/extract/sourcecode/a.html")).to be true
    expect(File.read("spec/assets/extract/sourcecode/sourcecode-0000.txt", encoding: "utf-8"))
      .to eq <<~OUTPUT.chomp
        def ruby(x)
          if x < 0 && x > 1
            return
          end
        end
      OUTPUT
    expect(File.read("spec/assets/extract/sourcecode/a.html", encoding: "utf-8"))
      .to eq <<~OUTPUT.chomp
        <html>
          <head>&amp;</head>
        </html>
      OUTPUT
    expect(File.exist?("spec/assets/extract/image/image-0000.png")).to be true
    expect(File.exist?("spec/assets/extract/image/image-0001.png")).to be false
    expect(File.exist?("spec/assets/extract/image/img1.png")).to be true
    expect(File.exist?("spec/assets/extract/requirement/requirement-0000.xml")).to be true
    expect(File.exist?("spec/assets/extract/requirement/requirement-0001.xml")).to be false
    expect(File.exist?("spec/assets/extract/requirement/permission-0001.xml")).to be false
    expect(File.exist?("spec/assets/extract/requirement/reqt1.xml")).to be true
  end

  it "warns when no standard type provided" do
    expect do
      Metanorma::Compile.new.compile("spec/assets/test.adoc", relaton: "testrelaton.xml", agree_to_terms: true)
    end.to output(/Please specify a standard type/).to_stdout
  end

  it "throw an error when bogus standard type requested" do
    expect do
      Metanorma::Compile.new
        .compile(
          "spec/assets/test.adoc",
          type: "bogus_format"
        )
    end.to output(/loading gem `metanorma-bogus_format` failed/).to_stdout
  end

  it "warns when bogus format requested" do
    expect do
      Metanorma::Compile.new.compile(
        "spec/assets/test.adoc",
        type: "iso",
        format: "bogus_format",
        agree_to_terms: true
      )
    end.to output(/Only source file format currently supported is 'asciidoc'/).to_stdout
  end

  it "warns when bogus extension requested" do
    expect do
      Metanorma::Compile.new.compile(
        "spec/assets/test.adoc",
        type: "iso",
        extension_keys: [:bogus_format],
        agree_to_terms: true
      )
    end.to output(/bogus_format format is not supported for this standard/).to_stdout
  end

  it "rewrites remote include paths" do
    Metanorma::Compile.new.compile("spec/assets/test2.adoc", type: "iso", extension_keys: [:xml])
    expect(File.exist?("spec/assets/test2.xml")).to be true
    xml = File.read("spec/assets/test2.xml", encoding: "utf-8")
    expect(xml).to include "ABC"
  end

  it "processes a Metanorma XML ISO document with CRLF line endings" do
    doc_name = "test_crlf.adoc"

    # convert LF -> CRLF
    doc = "spec/assets/#{doc_name}.xml"
    line_no = 0
    eol = Gem.win_platform? ? "\n" : "\r\n"
    File.open(doc, "w:UTF-8") do |output|
      File.readlines(doc, chomp: true).each do |line|
        if line_no == 3
          output.write(":mn-document-class: iso#{eol}")
          output.write(":mn-output-extensions: xml,html,doc,rxl#{eol}")
        end
        output.write("#{line}#{eol}")
        line_no += 1
      end
    end

    Metanorma::Compile.new.compile(doc)
    expect(File.exist?("spec/assets/#{doc_name}.xml")).to be true
  end

  private

  def mock_iso_processor_output(inname, outname, hash)
    require "metanorma-iso"
    expect(Metanorma::Registry.instance.find_processor(:iso)).to receive(:output)
      .with(an_instance_of(String), inname, outname, :presentation, hash).at_least :once
  end
end
