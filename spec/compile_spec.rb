require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Compile do
  def clean_outputs
    %w(xml presentation.xml html alt.html doc relaton.xml err rxl pdf)
      .each { |ext| FileUtils.rm_f Dir["spec/assets/*.#{ext}"] }

    FileUtils.rm_rf "spec/assets/test"
    FileUtils.rm_rf "spec/assets/extract"
    FileUtils.rm_f "*-error.log"
  end

  around(:each) do |example|
    clean_outputs
    example.run
    clean_outputs
  rescue SystemExit
    fail "Unexpected exit encountered"
  end

  it "passes asciidoc options onto isodoc" do
    mock_iso_processor_output(
      File.expand_path("spec/assets/test2.xml"),
      File.expand_path("spec/assets/test2.presentation.xml"),
      {
        bare: nil,
        datauriimage: true,
        breakupurlsintables: false,
        hierarchicalassets: false,
        usexinclude: true,
        suppressasciimathdup: true,
        no_install_fonts: nil,
        sectionsplit: nil,
        sourcefilename: "spec/assets/test2.adoc",
        sourcehighlighter: true,
        strict: nil,
        baseassetpath: "spec/assets",
        aligncrosselements: "p,table",
        tocfigures: true,
        toctables: true,
        tocrecommendations: true,
        output_formats: {
          presentation: "presentation.xml",
        },
      },
    )
    Metanorma::Compile.new.compile("spec/assets/test2.adoc",
                                   type: "iso",
                                   extension_keys: [:presentation],
                                   bare: nil,
                                   baseassetpath: "spec/assets",
                                   suppressasciimathdup: true,
                                   sectionsplit: nil,
                                   datauriimage: true,
                                   aligncrosselements: "p,table",
                                   tocfigures: true,
                                   toctables: true,
                                   tocrecommendations: true,
                                   agree_to_terms: true,
                                   output_formats: { doc: "doc",
                                                     html: "html",
                                                     html_alt: "alt.html",
                                                     isosts: "iso.sts.xml",
                                                     pdf: "pdf",
                                                     presentation: "presentation.xml",
                                                     rxl: "rxl",
                                                     sts: "sts.xml",
                                                     xml: "xml" })
  end

  it "fontist_install called" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install) {}
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).once

    compile.compile("spec/assets/test.adoc", type: "iso", agree_to_terms: true)
  end

  it "fontist_install called with explicit no_install_fonts=false" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install) {}
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).once

    compile.compile("spec/assets/test.adoc", type: "iso",
                                             agree_to_terms: true,
                                             no_install_fonts: false)
  end

  it "skip font install with no_install_fonts" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install) {}
    expect(Metanorma::Util::FontistHelper).not_to receive(:fontist_install)

    compile.compile("spec/assets/test.adoc", type: "iso",
                                             no_install_fonts: true)
  end

  it "exit on license error" do
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .and_raise(Fontist::Errors::LicensingError)

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "skip license error" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .and_raise(Fontist::Errors::LicensingError)
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).once

    compile.compile("spec/assets/test.adoc", type: "iso",
                                             continue_without_fonts: true)
  end

  it "exit on license error" do
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .and_raise(Fontist::Errors::LicensingError)
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).once

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "exit on missing fonts" do
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .and_raise(Fontist::Errors::FontError.new("Font 'SomeFont' not found"))
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).once

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "handle on missing fonts" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .and_raise(Fontist::Errors::FontError.new("Font 'SomeFont' not found"))
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).once

    compile.compile("spec/assets/test.adoc", type: "iso",
                                             continue_without_fonts: true)
  end

  it "handle missing fontist index" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    @called = 0
    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install) do
      @called += 1
      raise Fontist::Errors::FormulaIndexNotFoundError if @called == 1
    end
    allow(Fontist::Formula).to receive(:update_formulas_repo)
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).twice

    compile.compile("spec/assets/test.adoc", type: "iso",
                                             continue_without_fonts: true)
  end

  it "exit on twice missing fontist index" do
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .and_raise(Fontist::Errors::FormulaIndexNotFoundError)

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "exit on not supported font after missing fontist index" do
    compile = Metanorma::Compile.new

    @called = 0
    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install) do
      @called += 1
      raise Fontist::Errors::FormulaIndexNotFoundError if @called == 1
      raise Fontist::Errors::UnsupportedFontError.new("TestFnt") if @called == 2
    end
    allow(Fontist::Formula).to receive(:update_formulas_repo)
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).twice

    expect do
      compile.compile("spec/assets/test.adoc", type: "iso")
    end.to raise_error SystemExit
  end

  it "handle not supported font after missing fontist index" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    @called = 0
    allow(Metanorma::Util::FontistHelper).to receive(:fontist_install) do
      @called += 1
      raise Fontist::Errors::FormulaIndexNotFoundError if @called == 1
      raise Fontist::Errors::UnsupportedFontError.new("TestFnt") if @called == 2
    end
    allow(Fontist::Formula).to receive(:update_formulas_repo)
    allow(Fontist::Manifest::Locations).to receive(:from_hash)
    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install).twice

    compile.compile("spec/assets/test.adoc", type: "iso",
                                             continue_without_fonts: true)
  end

  it "handle no_progress" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    expect(Metanorma::Util::FontistHelper).to receive(:fontist_install)
      .with(anything, false, true)

    compile.compile("spec/assets/test.adoc", type: "iso", no_progress: true)
  end

  it "handle :fonts attribute in adoc" do
    mock_pdf
    mock_sts
    compile = Metanorma::Compile.new

    allow(Metanorma::Util::FontistHelper).to receive(:install_fonts_safe)
      .with(hash_including("MS Gothic"), false, false, false)
      .and_return(nil)

    allow(Metanorma::Util::FontistHelper).to receive(:location_manifest)
      .with(anything, anything)
      .and_return({})

    compile.compile("spec/assets/custom_fonts.adoc", type: "iso")
  end

  it "processes metanorma options inside Asciidoc" do
    Metanorma::Compile.new.compile("spec/assets/test1.adoc",
                                   agree_to_terms: true)
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
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be true
    expect(File.exist?("spec/assets/test.alt.html")).to be true
  end

  it "processes all extensions of an asciidoc ISO document" do
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   extension_keys: [:all],
                                   agree_to_terms: true)
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
    Metanorma::Compile.new.compile(
      "spec/examples/metanorma-collection/dummy.adoc",
      output_dir: "spec/assets",
      agree_to_terms: true,
    )
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
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    FileUtils.rm_f(%w(test.html test.alt.html test.doc)
      .map { |f| "spec/assets/#{f}" })
    expect do
      Metanorma::Compile.new.compile("spec/assets/test.xml")
    end.not_to output(/Error: Please specify a standard type/).to_stdout
    expect(File.exist?("spec/assets/test.html")).to be true
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "ISO copyright office"
  end

  it "extracts isodoc options from asciidoc file" do
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   extension_keys: [:html],
                                   agree_to_terms: true)
    html = File.read("spec/assets/test.html", encoding: "utf-8")
    expect(html).to include "font-family: body-font;"
    expect(html).to include "font-family: header-font;"
    expect(html).to include "font-family: monospace-font;"
  end

  it "inserts RXL extension key" do
    FileUtils.rm_f("spec/assets/test.rxl")
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      extension_keys: [:html],
      agree_to_terms: true,
    )
    expect(File.exist?("spec/assets/test.rxl")).to be false
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      extension_keys: [:html],
      agree_to_terms: true,
      site_generate: true,
    )
    expect(File.exist?("spec/assets/test.rxl")).to be true
  end

  it "wraps HTML output" do
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      wrapper: true,
      extension_keys: [:html],
      agree_to_terms: true,
    )
    expect(File.exist?("spec/assets/test/test.html")).to be true
  end

  it "data64 encodes images" do
    Metanorma::Compile.new.compile(
      "spec/assets/test.adoc",
      type: "iso",
      datauriimage: true,
      extension_keys: [:html],
      agree_to_terms: true,
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
      agree_to_terms: true,
    )
    expect(File.exist?("spec/assets/testrelaton.xml")).to be true
    xml = File.read("spec/assets/testrelaton.xml", encoding: "utf-8")
    expect(xml).to include %(<bibdata type="standard">)
  end

  it "exports bibdata, rxl" do
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   extension_keys: [:rxl],
                                   agree_to_terms: true)
    expect(File.exist?("spec/assets/test.rxl")).to be true
    xml = File.read("spec/assets/test.rxl", encoding: "utf-8")
    expect(xml).to include %(<bibdata type="standard">)
  end

  it "exports assets" do
    sourcecode = "spec/assets/extract/sourcecode"
    %w(sourcecode-0000.txt sourcecode-0001.txt a.html).each do |w|
      FileUtils.rm_f "#{sourcecode}/#{w}"
    end
    %w(image-0000.png image-0001.png img1.png).each do |w|
      FileUtils.rm_f "#{sourcecode}/image/#{w}"
    end
    %w(requirement-0000.xml requirement-0001.xml permission-0001.xml reqt1.xml)
      .each do |w|
      FileUtils.rm_f "#{sourcecode}/requirement/#{w}"
    end
    Metanorma::Compile.new.compile(
      "spec/assets/test_datauri.adoc",
      type: "iso",
      extract: "spec/assets/extract",
      extract_type: %i(sourcecode image requirement),
      extension_keys: %i(xml html),
      agree_to_terms: true,
    )

    expect(File.exist?("spec/assets/test_datauri.xml")).to be true
    expect(File.exist?("#{sourcecode}/sourcecode-0000.txt")).to be true
    expect(File.exist?("#{sourcecode}/sourcecode-0001.txt")).to be false
    expect(File.exist?("#{sourcecode}/a.html")).to be true
    expect(File.read("#{sourcecode}/sourcecode-0000.txt", encoding: "utf-8"))
      .to eq <<~OUTPUT.chomp
        def ruby(x)
          if x < 0 && x > 1
            return
          end
        end
      OUTPUT
    # expect(File.read("#{sourcecode}/a.html", encoding: "utf-8"))
    #  .to eq <<~OUTPUT.chomp
    #   <html>
    #    <head>&</head>
    # </html>
    # OUTPUT
    expect(File.exist?("spec/assets/extract/image/image-0000.png")).to be true
    expect(File.exist?("spec/assets/extract/image/image-0001.png")).to be false
    expect(File.exist?("spec/assets/extract/image/img1.png")).to be true
    expect(File.exist?("spec/assets/extract/requirement/requirement-0000.xml"))
      .to be true
    expect(File.exist?("spec/assets/extract/requirement/requirement-0001.xml"))
      .to be false
    expect(File.exist?("spec/assets/extract/requirement/permission-0001.xml"))
      .to be false
    expect(File.exist?("spec/assets/extract/requirement/reqt1.xml")).to be true
  end

  it "warns when no standard type provided" do
    expect do
      supress_exit do
        Metanorma::Compile.new
          .compile(
            "spec/assets/test.adoc",
            relaton: "testrelaton.xml",
            agree_to_terms: true,
          )
      end
    end.to output(/Please specify a standard type/).to_stdout
  end

  it "throw an error when bogus standard type requested" do
    expect do
      supress_exit do
        Metanorma::Compile.new
          .compile(
            "spec/assets/test.adoc",
            type: "bogus_format",
          )
      end
    end.to output(/cannot load such file -- metanorma-bogus_format/).to_stdout
  end

  it "warns when bogus format requested" do
    expect do
      supress_exit do
        Metanorma::Compile.new.compile(
          "spec/assets/test.adoc",
          type: "iso",
          format: "bogus_format",
          agree_to_terms: true,
        )
      end
    end.to output(/Only source file format currently supported is 'asciidoc'/)
      .to_stdout
  end

  it "warns when bogus extension requested" do
    expect do
      supress_exit do
        Metanorma::Compile.new.compile(
          "spec/assets/test.adoc",
          type: "iso",
          extension_keys: [:bogus_format],
          agree_to_terms: true,
        )
      end
    end.to output(/bogus_format format is not supported for this standard/)
      .to_stdout
  end

  it "rewrites remote include paths" do
    Metanorma::Compile.new.compile("spec/assets/test2.adoc",
                                   type: "iso",
                                   extension_keys: [:xml])
    expect(File.exist?("spec/assets/test2.xml")).to be true
    xml = File.read("spec/assets/test2.xml", encoding: "utf-8")
    expect(xml).to include "ABC"
    expect(xml).to include "<stem"
  end

  it "processes a Metanorma XML ISO document with CRLF line endings" do
    doc_name = "spec/assets/test_crlf"
    docfile = "#{doc_name}.adoc"

    # convert LF -> CRLF
    eol = "\n" # Gem.win_platform? ? "\n" : "\r\n"
    File.open(docfile, "w:UTF-8") do |output|
      File.readlines("spec/assets/test1.adoc", chomp: true)
        .each do |line|
          output.write("#{line}#{eol}")
        end
    end

    Metanorma::Compile.new.compile(docfile)
    expect(File.exist?("#{doc_name}.xml")).to be true
  end

  it "don't skip mn2pdf errors" do
    exception_msg = "[mn2pdf] Fatal:"
    allow(Mn2pdf).to receive(:convert).and_raise(exception_msg)

    c = Metanorma::Compile.new
    c.compile("spec/assets/test2.adoc", type: "iso", extension_keys: [:pdf])

    expect(c.errors).to include(exception_msg)
  end

  it "don't skip Presentation XML errors" do
    require "metanorma-iso"
    allow_any_instance_of(IsoDoc::Iso::HtmlConvert).to receive(:convert)
      .and_raise("Something")
    c = Metanorma::Compile.new
    c.compile("spec/assets/test2.adoc", type: "iso", extension_keys: [:html],
                                        strict: true)
    expect(c.errors).not_to include("Anything")
    expect(c.errors).to include("Something")

    allow_any_instance_of(IsoDoc::Iso::PresentationXMLConvert)
      .to receive(:convert)
      .and_raise("Anything")
    c = Metanorma::Compile.new
    c.compile("spec/assets/test2.adoc", type: "iso", extension_keys: [:html],
                                        strict: true)
    expect(c.errors).to include("Anything")
    expect(c.errors).not_to include("Something") # never runs HTML
  end

  it "processes section split HTML" do
    FileUtils.rm_rf "test_collection"
    FileUtils.rm_rf "test_files"
    mock_render
    Metanorma::Compile.new.compile("spec/fixtures/test_sectionsplit.xml",
                                   type: "iso",
                                   extension_keys: %i[presentation html],
                                   bare: nil,
                                   sectionsplit: "true",
                                   datauriimage: true,
                                   agree_to_terms: true)
    f = "spec/fixtures/test_sectionsplit.html_collection"
    expect(File.exist?("#{f}/index.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.0.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.1.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.2.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.3.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.4.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.5.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.6.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.7.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.8.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.9.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.10.html")).to be false
    f = Dir.glob("spec/fixtures/test_sectionsplit_*_files").first
    expect(File.exist?("#{f}/cover.html")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.0.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.1.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.2.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.3.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.4.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.5.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.6.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.7.xml")).to be true
    expect(File.exist?("#{f}/test_sectionsplit.html.8.xml")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.9.xml")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.10.xml")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.html.yaml")).to be true
    m = /type="([^"]+)"/.match(File.read("#{f}/test_sectionsplit.html.0.xml"))
    file2 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.3.xml"))
    file2.xpath("//xmlns:emf").each(&:remove)
    expect(file2.at("//xmlns:p[@id = 'middletitle']")).not_to be_nil
    expect(file2.at("//xmlns:note[@id = 'middlenote']")).not_to be_nil
    expect(xmlpp(file2
     .at("//xmlns:eref[@bibitemid = '#{m[1]}_A']").to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
        <eref bibitemid="#{m[1]}_A" type="#{m[1]}">HE<localityStack><locality type="anchor"><referenceFrom>A</referenceFrom></locality></localityStack></eref>
      OUTPUT
    expect(xmlpp(file2
     .at("//xmlns:note[@id = 'N1']//xmlns:eref[@bibitemid = '#{m[1]}_R1']")
      .to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
        <eref bibitemid="#{m[1]}_R1" type="#{m[1]}">SHE<localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></eref>
      OUTPUT
    expect(xmlpp(file2
     .at("//xmlns:note[@id = 'N2']//xmlns:eref[@bibitemid = '#{m[1]}_R1']")
      .to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
        <eref bibitemid="#{m[1]}_R1" type="#{m[1]}"><image src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/><localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></eref>
      OUTPUT
    expect(file2
     .at("//xmlns:bibitem[@id = 'R1']"))
      .to be_nil
    expect(xmlpp(file2
     .at("//xmlns:bibitem[@id = '#{m[1]}_A']").to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
        <bibitem id="#{m[1]}_A" type="internal">
        <docidentifier type="repository">#{m[1]}/A</docidentifier>
        </bibitem>
      OUTPUT
    expect(xmlpp(file2
     .at("//xmlns:bibitem[@id = '#{m[1]}_R1']").to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
        <bibitem id="#{m[1]}_R1" type="internal">
        <docidentifier type="repository">#{m[1]}/R1</docidentifier>
        </bibitem>
      OUTPUT
    expect(xmlpp(file2
     .at("//xmlns:svgmap[1]").to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
        <svgmap><figure>
        <image src="" mimetype="image/svg+xml" height="auto" width="auto">
          <svg xmlns="http://www.w3.org/2000/svg">
            <a href="A">A</a>
            <a href="B">B</a>
          </svg>
          </image>
          <target href="B">
            <eref type="#{m[1]}" bibitemid="#{m[1]}_R1">R1<localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></eref>
          </target>
        </figure>
        <target href="A"><eref bibitemid="#{m[1]}_A" type="#{m[1]}">A<localityStack><locality type="anchor"><referenceFrom>A</referenceFrom></locality></localityStack></eref></target><target href="B"><eref bibitemid="#{m[1]}_B" type="#{m[1]}">B<localityStack><locality type="anchor"><referenceFrom>B</referenceFrom></locality></localityStack></eref></target></svgmap>
      OUTPUT
    expect(xmlpp(file2
     .at("//xmlns:svgmap[2]").to_xml))
      .to be_equivalent_to xmlpp(<<~OUTPUT)
             <svgmap><figure>
         <image src="" mimetype="image/svg+xml" height="auto" width="auto"><svg xmlns="http://www.w3.org/2000/svg">
           <a href="P">P</a>
         </svg></img>
        </figure><target href="P"><eref bibitemid="#{m[1]}_P" type="#{m[1]}">P<localityStack><locality type="anchor"><referenceFrom>P</referenceFrom></locality></localityStack></eref></target></svgmap>
      OUTPUT
    expect(file2.at("//xmlns:preface")).to be_nil
    expect(file2.at("//xmlns:sections/xmlns:clause")).not_to be_nil
    expect(file2.at("//xmlns:annex")).to be_nil
    expect(file2.at("//xmlns:indexsect")).to be_nil
    #     file4 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.4.xml"))
    #     expect(xmlpp(file4
    #      .at("//xmlns:bibitem[@id = '#{m[1]}_R1']").to_xml))
    #       .to be_equivalent_to xmlpp(<<~OUTPUT)
    # <bibitem id="#{m[1]}_R1">
    #   <formattedref><em><span class="stddocTitle">Hello</span></em>.</formattedref>
    #   <docidentifier>R1</docidentifier>
    #   <biblio-tag>R1, </biblio-tag>
    # </bibitem>
    #       OUTPUT
    file6 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.6.xml"))
    expect(file6.at("//xmlns:preface")).to be_nil
    expect(file6.at("//xmlns:sections/xmlns:clause")).to be_nil
    expect(file6.at("//xmlns:annex")).not_to be_nil
    expect(file6.at("//xmlns:indexsect")).to be_nil
    expect(File.read("#{f}/test_sectionsplit.html.html.yaml"))
      .to be_equivalent_to <<~OUTPUT
        ---
        directives:
        - presentation-xml
        - bare-after-first
        bibdata:
          title:
            type: title-main
            language:
            content: ISO Title
          type: collection
          docid:
            type: ISO
            id: ISO 1
        manifest:
          level: collection
          title: Collection
          docref:
          - fileref: test_sectionsplit.html.0.xml
            identifier: Contents
          - fileref: test_sectionsplit.html.1.xml
            identifier: abstract
          - fileref: test_sectionsplit.html.2.xml
            identifier: introduction
          - fileref: test_sectionsplit.html.4.xml
            identifier: 1 Normative References
          - fileref: test_sectionsplit.html.3.xml
            identifier: 2 Clause 4
          - fileref: test_sectionsplit.html.5.xml
            identifier: Annex A <span class="obligation">(normative)</span>  Annex (informative)
          - fileref: test_sectionsplit.html.6.xml
            identifier: Annex B <span class="obligation">(normative)</span>  Annex 2
          - fileref: test_sectionsplit.html.7.xml
            identifier: Bibliography

      OUTPUT
  end

  it "use threads number from METANORMA_PARALLEL" do
    expect(ENV).to receive(:[]).with("METANORMA_PARALLEL").and_return(1)
    allow(ENV).to receive(:[]).and_call_original
    expect(Metanorma::Util::WorkersPool).to receive(:new).with(1)
      .and_call_original
    mock_pdf
    mock_sts
    Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                   type: "iso",
                                   agree_to_terms: true)
    expect(File.exist?("spec/assets/test.xml")).to be true
    expect(File.exist?("spec/assets/test.doc")).to be true
    expect(File.exist?("spec/assets/test.html")).to be true
    expect(File.exist?("spec/assets/test.alt.html")).to be true
    # this isn't really testing threads
  end

  it "error log generated on missing flavor" do
    error_log_file = "#{Date.today}-error.log"

    expect do
      Metanorma::Compile.new.compile("spec/assets/test.adoc",
                                     type: "missing-flavor",
                                     agree_to_terms: true)
    end.to raise_error SystemExit

    expect(File.exist?(error_log_file)).to be true
  end

  private

  def mock_render
    original_add = Metanorma::Collection::Renderer.method(:render)
    allow(Metanorma::Collection::Renderer)
      .to receive(:render) do |col, opts|
      original_add.call(col, opts.merge(compile: { no_install_fonts: true }))
    end
  end

  def mock_iso_processor_output(inname, outname, hash)
    require "metanorma-iso"
    expect(Metanorma::Registry.instance.find_processor(:iso))
      .to receive(:output).with(
        an_instance_of(String),
        inname,
        outname,
        :presentation,
        hash,
      ).at_least :once
  end
end
