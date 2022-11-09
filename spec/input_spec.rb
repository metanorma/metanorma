require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Input::Asciidoc do
  it "aborts if include error" do
    require "metanorma-iso"
    input = <<~INPUT
      = Document title
      Author
      :docfile: test.adoc
      :nodoc:

      include::common/common-sections/00-abstract.adoc[]

    INPUT
    expect do
      Metanorma::Input::Asciidoc.new
        .process(input, "test.adoc", :iso)
    end.to raise_error(SystemExit)
  rescue SystemExit
  end

  it "extracts Asciidoctor document attributes" do
    input = <<~INPUT
      = Document title
      Author
      :sectionsplit: a
      :body-font: b
      :header-font: c
      :title-font: d
      :i18nyaml: e
      :htmlstylesheet: f
      :htmlcoverpage: g
      :htmlintropage: h
      :scripts: i
      :scripts-pdf: j
      :wordstylesheet: k
      :standardstylesheet: l
      :header: m
      :wordcoverpage: n
      :wordintropage: o
      :ulstyle: p
      :olstyle: q
      :data-uri-image: false
      :htmltoclevels: r
      :doctoclevels: s
      :hierarchical-assets: t
      :use-xinclude: u
      :break-up-urls-in-tables: v
      :bare: w
      :htmlstylesheet-override: x
      :wordstylesheet-override: y
      :scripts-override: z
      :suppress-asciimath-dup: true
      :base-asset-path: aa
      :align-cross-elements: ab
      :pdf-encrypt: ac
      :pdf-encryption-length: ad
      :pdf-user-password: ae
      :pdf-owner-password: af
      :pdf-allow-copy-content: ag
      :pdf-allow-edit-content: ah
      :pdf-allow-assemble-document: ai
      :pdf-allow-edit-annotations: aj
      :pdf-allow-print: ak
      :pdf-allow-print-hq: al
      :pdf-allow-fill-in-forms: am
      :pdf-allow-access-content: an
      :pdf-encrypt-metadata: ao
      :toc-figures: ap
      :toc-tables: aq
      :toc-recommendations: ar
      :fonts: as
      :font-license-agreement: at
      :iso-word-template: au
      :document-scheme: av
      :ieee-dtd: aw
      :localize-number: ax
      :iso-word-bg-strip-color: ay
      :modspec-identifier-base: az
      :toclevels: ba
    INPUT
    output = <<~OUTPUT
      {:aligncrosselements=>"ab", :bare=>"w", :baseassetpath=>"aa", :bodyfont=>"b", :break_up_urls_in_tables=>"v", :datauriimage=>false, :doctoclevels=>"s", :documentscheme=>"av", :fontlicenseagreement=>"at", :fonts=>"as", :header=>"m", :headerfont=>"c", :hierarchical_assets=>"t", :htmlcoverpage=>"g", :htmlintropage=>"h", :htmlstylesheet=>"f", :htmlstylesheet_override=>"x", :htmltoclevels=>"r", :i18nyaml=>"e", :ieeedtd=>"aw", :isowordbgstripcolor=>"ay", :isowordtemplate=>"au", :localizenumber=>"ax", :modspecidentifierbase=>"az", :olstyle=>"q", :pdfallowaccesscontent=>"an", :pdfallowassembledocument=>"ai", :pdfallowcopycontent=>"ag", :pdfalloweditannotations=>"aj", :pdfalloweditcontent=>"ah", :pdfallowfillinforms=>"am", :pdfallowprint=>"ak", :pdfallowprinthq=>"al", :pdfencrypt=>"ac", :pdfencryptionlength=>"ad", :pdfencryptmetadata=>"ao", :pdfownerpassword=>"af", :pdfuserpassword=>"ae", :scripts=>"i", :scripts_override=>"z", :scripts_pdf=>"j", :sectionsplit=>"a", :standardstylesheet=>"l", :suppressasciimathdup=>true, :titlefont=>"d", :tocfigures=>"ap", :toclevels=>"ba", :tocrecommendations=>"ar", :toctables=>"aq", :ulstyle=>"p", :use_xinclude=>"u", :wordcoverpage=>"n", :wordintropage=>"o", :wordstylesheet=>"k", :wordstylesheet_override=>"y"}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
        .extract_options(input).sort.to_h.to_s + "\n").to eq output
  end

  it "extracts Asciidoctor document attributes with default values" do
    input = <<~INPUT
      = Document title
      Author
      :hierarchical-assets:
      :use-xinclude:
      :break-up-urls-in-tables:
      :suppress-asciimath-dup:
    INPUT
    output = <<~OUTPUT
      {:break_up_urls_in_tables=>"true", :datauriimage=>true, :hierarchical_assets=>"true", :suppressasciimathdup=>true, :use_xinclude=>"true"}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
      .extract_options(input).sort.to_h.to_s + "\n").to eq output
  end

  it "extracts Asciidoctor document attributes for Metanorma" do
    input = <<~INPUT
      = Document title
      Author
      :mn-document-class: a
      :mn-output-extensions: b
      :mn-keep-asciimath:
    INPUT
    output = <<~OUTPUT
      {:asciimath=>true, :extensions=>"b", :type=>"a"}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
      .extract_metanorma_options(input).sort.to_h.to_s + "\n").to eq output
  end

  it "extracts Asciidoctor document attributes for Metanorma" do
    input = <<~INPUT
      = Document title
      Author
    INPUT
    output = <<~OUTPUT
      {}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
      .extract_metanorma_options(input).sort.to_h.to_s + "\n").to eq output
  end
end
