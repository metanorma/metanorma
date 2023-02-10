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
      :source-highlighter: bb
    INPUT
    output = <<~OUTPUT
      {:aligncrosselements=>"ab", :bare=>"w", :baseassetpath=>"aa", :bodyfont=>"b", :breakupurlsintables=>true, :datauriimage=>false, :doctoclevels=>"s", :documentscheme=>"av", :fontlicenseagreement=>"at", :fonts=>"as", :header=>"m", :headerfont=>"c", :hierarchicalassets=>true, :htmlcoverpage=>"g", :htmlintropage=>"h", :htmlstylesheet=>"f", :htmlstylesheet_override=>"x", :htmltoclevels=>"r", :i18nyaml=>"e", :ieeedtd=>"aw", :isowordbgstripcolor=>"ay", :isowordtemplate=>"au", :localizenumber=>"ax", :modspecidentifierbase=>"az", :olstyle=>"q", :pdfallowaccesscontent=>"an", :pdfallowassembledocument=>"ai", :pdfallowcopycontent=>"ag", :pdfalloweditannotations=>"aj", :pdfalloweditcontent=>"ah", :pdfallowfillinforms=>"am", :pdfallowprint=>"ak", :pdfallowprinthq=>"al", :pdfencrypt=>"ac", :pdfencryptionlength=>"ad", :pdfencryptmetadata=>"ao", :pdfownerpassword=>"af", :pdfuserpassword=>"ae", :scripts=>"i", :scripts_override=>"z", :scripts_pdf=>"j", :sectionsplit=>"a", :sourcehighlighter=>true, :standardstylesheet=>"l", :suppressasciimathdup=>true, :titlefont=>"d", :tocfigures=>true, :toclevels=>"ba", :tocrecommendations=>true, :toctables=>true, :ulstyle=>"p", :usexinclude=>true, :wordcoverpage=>"n", :wordintropage=>"o", :wordstylesheet=>"k", :wordstylesheet_override=>"y"}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
        .extract_options(input).sort.to_h.to_s + "\n").to eq output

    input = <<~INPUT
      = Document title
      Author
      :sectionsplit:   a#{'   '}
      :body-font:   b#{'   '}
      :header-font:   c#{'   '}
      :title-font:   d#{'   '}
      :i18nyaml:   e#{'   '}
      :htmlstylesheet:   f#{'   '}
      :htmlcoverpage:   g#{'   '}
      :htmlintropage:   h#{'   '}
      :scripts:   i#{'   '}
      :scripts-pdf:   j#{'   '}
      :wordstylesheet:   k#{'   '}
      :standardstylesheet:   l#{'   '}
      :header:   m#{'   '}
      :wordcoverpage:   n#{'   '}
      :wordintropage:   o#{'   '}
      :ulstyle:   p#{'   '}
      :olstyle:   q#{'   '}
      :data-uri-image:   false#{'   '}
      :htmltoclevels:   r#{'   '}
      :doctoclevels:   s#{'   '}
      :hierarchical-assets:   t#{'   '}
      :use-xinclude:   u#{'   '}
      :break-up-urls-in-tables:   v#{'   '}
      :bare:   w#{'   '}
      :htmlstylesheet-override:   x#{'   '}
      :wordstylesheet-override:   y#{'   '}
      :scripts-override:   z#{'   '}
      :suppress-asciimath-dup:   true#{'   '}
      :base-asset-path:   aa#{'   '}
      :align-cross-elements:   ab#{'   '}
      :pdf-encrypt:   ac#{'   '}
      :pdf-encryption-length:   ad#{'   '}
      :pdf-user-password:   ae#{'   '}
      :pdf-owner-password:   af#{'   '}
      :pdf-allow-copy-content:   ag#{'   '}
      :pdf-allow-edit-content:   ah#{'   '}
      :pdf-allow-assemble-document:   ai#{'   '}
      :pdf-allow-edit-annotations:   aj#{'   '}
      :pdf-allow-print:   ak#{'   '}
      :pdf-allow-print-hq:   al#{'   '}
      :pdf-allow-fill-in-forms:   am#{'   '}
      :pdf-allow-access-content:   an#{'   '}
      :pdf-encrypt-metadata:   ao#{'   '}
      :toc-figures:   ap#{'   '}
      :toc-tables:   aq#{'   '}
      :toc-recommendations:   ar#{'   '}
      :fonts:   as#{'   '}
      :font-license-agreement:   at#{'   '}
      :iso-word-template:   au#{'   '}
      :document-scheme:   av#{'   '}
      :ieee-dtd:   aw#{'   '}
      :localize-number:   ax#{'   '}
      :iso-word-bg-strip-color:   ay#{'   '}
      :modspec-identifier-base:   az#{'   '}
      :toclevels:   ba#{'   '}
      :source-highlighter:   bb#{'   '}
    INPUT
    expect(Metanorma::Input::Asciidoc.new
        .extract_options(input).sort.to_h.to_s + "\n").to eq output
  end

  it "extracts Asciidoctor document attributes with default values" do
    input = <<~INPUT
      = Document title
      Author

    INPUT
    output = <<~OUTPUT
      {:breakupurlsintables=>false, :datauriimage=>true, :hierarchicalassets=>false, :sourcehighlighter=>true, :suppressasciimathdup=>true, :tocfigures=>false, :tocrecommendations=>false, :toctables=>false, :usexinclude=>true}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
      .extract_options(input).sort.to_h.to_s + "\n").to eq output
  end

  it "extracts Asciidoctor document attributes with default values and empty settings" do
    input = <<~INPUT
      = Document title
      Author
      :hierarchical-assets:
      :use-xinclude:
      :break-up-urls-in-tables:
      :suppress-asciimath-dup:
      :toc-tables:
      :toc-figures:
      :toc-recommendations
      :datauriimage:
      :source-highlighter:
    INPUT
    output = <<~OUTPUT
      {:breakupurlsintables=>true, :datauriimage=>true, :hierarchicalassets=>true, :sourcehighlighter=>true, :suppressasciimathdup=>true, :tocfigures=>true, :tocrecommendations=>false, :toctables=>true, :usexinclude=>true}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
      .extract_options(input).sort.to_h.to_s + "\n").to eq output
  end

  it "extracts Asciidoctor document attributes with default values and contrary settings" do
    input = <<~INPUT
      = Document title
      Author
      :hierarchical-assets: false
      :use-xinclude: false
      :break-up-urls-in-tables: true
      :suppress-asciimath-dup: true
      :toc-tables: false
      :toc-figures: false
      :toc-recommendations: false
      :data-uri-image: false
      :source-highlighter: false
    INPUT
    output = <<~OUTPUT
      {:breakupurlsintables=>true, :datauriimage=>false, :hierarchicalassets=>false, :sourcehighlighter=>false, :suppressasciimathdup=>true, :tocfigures=>false, :tocrecommendations=>false, :toctables=>false, :usexinclude=>false}
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
      :mn-relaton-output-file: c
      :mn-keep-asciimath:
    INPUT
    output = <<~OUTPUT
      {:asciimath=>true, :extensions=>"b", :relaton=>"c", :type=>"a"}
    OUTPUT
    expect(Metanorma::Input::Asciidoc.new
      .extract_metanorma_options(input).sort.to_h.to_s + "\n").to eq output

    input = <<~INPUT
      = Document title
      Author
      :mn-document-class:  a#{' '}
      :mn-output-extensions:  b#{' '}
      :mn-relaton-output-file:  c#{' '}
      :mn-keep-asciimath:
    INPUT
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
