require "spec_helper"
require "stringio"
require "isodoc"

def capture_stdout
  old = $stdout
  $stdout = fake = StringIO.new
  yield
  fake.string
ensure
  $stdout = old
end

INPATH = "spec/fixtures/collection".freeze
OUTPATH = "spec/fixtures/output".freeze

# rubocop:disable Layout/LineLength
RSpec.describe Metanorma::Collection do
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
    expect(File.exist?("#{f}/_test_sectionsplit_attachments/LICENSE.TXT")).to be true
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
    expect(Canon.format_xml(file2
      .at("//xmlns:fmt-eref[@bibitemid = '#{m[1]}_A']").to_xml.sub(/ id="[^"]+"/, "")))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <fmt-eref bibitemid="#{m[1]}_A" type="#{m[1]}">HE<localityStack><locality type="anchor"><referenceFrom>A</referenceFrom></locality></localityStack></fmt-eref>
      OUTPUT
    expect(Canon.format_xml(file2
     .at("//xmlns:note[@id = 'N1']//xmlns:fmt-eref[@bibitemid = '#{m[1]}_R1']")
      .to_xml.sub(/ id="[^"]+"/, "")))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <fmt-eref bibitemid="#{m[1]}_R1" type="#{m[1]}">SHE<localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></fmt-eref>
      OUTPUT
    expect(Canon.format_xml(file2
     .at("//xmlns:note[@id = 'N2']//xmlns:fmt-eref[@bibitemid = '#{m[1]}_R1']")
      .to_xml.sub(/ id="[^"]+"/, "")))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <fmt-eref bibitemid="#{m[1]}_R1" type="#{m[1]}"><image src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/><localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></fmt-eref>
      OUTPUT
    expect(Canon.format_xml(file2
     .at("//xmlns:note[@id = 'N3']//xmlns:fmt-link")
      .to_xml.sub(/ id="[^"]+"/, "").sub(/ id="[^"]+"/, "")))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <fmt-link attachment="true" target="_test_sectionsplit_attachments/LICENSE.TXT">License A</fmt-link>
      OUTPUT
    expect(file2
     .at("//xmlns:bibitem[@id = 'R1']"))
      .to be_nil
    expect(Canon.format_xml(file2
     .at("//xmlns:bibitem[@id = '#{m[1]}_A']").to_xml))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <bibitem id="#{m[1]}_A" anchor="#{m[1]}_A" type="internal">
        <docidentifier type="repository">#{m[1]}/A</docidentifier>
        </bibitem>
      OUTPUT
    expect(Canon.format_xml(file2
     .at("//xmlns:bibitem[@id = '#{m[1]}_R1']").to_xml))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <bibitem id="#{m[1]}_R1" anchor="#{m[1]}_R1" type="internal">
        <docidentifier type="repository">#{m[1]}/R1</docidentifier>
        </bibitem>
      OUTPUT
    expect(Canon.format_xml(file2
      .at("//xmlns:svgmap[1]").to_xml.gsub(/ (source|id)="[^"]+"/, "")))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
        <svgmap><figure>
        <image src="" mimetype="image/svg+xml" height="auto" width="auto">
          <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" x="0px" y="0px" viewBox="0 0 595.28 841.89" style="enable-background:new 0 0 595.28 841.89;" xml:space="preserve" semx-id="Layer_1_000000000" original-id="Layer_1_000000000" preserveaspectratio="xMidYMin slice">
               <image style="overflow:visible;" width="1" height="1" xlink:href="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/>
            <a href="A">A</a>
            <a href="B">B</a>
          </svg>
          </image>
          <target href="B">
          <eref bibitemid="R1" citeas="R1"/><semx element="eref">
            <fmt-eref type="#{m[1]}" bibitemid="#{m[1]}_R1">R1<localityStack><locality type="anchor"><referenceFrom>R1</referenceFrom></locality></localityStack></fmt-eref></semx>
          </target>
        </figure>
        <target href="A">
          <fmt-eref bibitemid="#{m[1]}_A" type="#{m[1]}">A<localityStack><locality type="anchor"><referenceFrom>A</referenceFrom></locality></localityStack></fmt-eref>
        </target>
        <target href="B">
          <fmt-eref bibitemid="#{m[1]}_B" type="#{m[1]}">B<localityStack><locality type="anchor"><referenceFrom>B</referenceFrom></locality></localityStack></fmt-eref>
        </target></svgmap>
      OUTPUT
    expect(Canon.format_xml(file2
     .at("//xmlns:svgmap[2]").to_xml.gsub(/ (source|id)="[^"]+"/, "")))
      .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
             <svgmap><figure>
         <image src="" mimetype="image/svg+xml" height="auto" width="auto">
          <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" x="0px" y="0px" viewBox="0 0 595.28 841.89" style="enable-background:new 0 0 595.28 841.89;" xml:space="preserve" semx-id="Layer_1_000000000" preserveaspectratio="xMidYMin slice">
               <image style="overflow:visible;" width="1" height="1" xlink:href="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/>
           <a href="P">P</a>
         </svg></img>
        </figure>
        <target href="P"><fmt-eref bibitemid="#{m[1]}_P" type="#{m[1]}">P<localityStack><locality type="anchor"><referenceFrom>P</referenceFrom></locality></localityStack></fmt-eref>
        </target></svgmap>
      OUTPUT
    expect(file2.at("//xmlns:preface")).to be_nil
    expect(file2.at("//xmlns:sections/xmlns:clause")).not_to be_nil
    expect(file2.at("//xmlns:annex")).to be_nil
    expect(file2.at("//xmlns:indexsect")).to be_nil
    #     file4 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.4.xml"))
    #     expect(Canon.format_xml(file4
    #      .at("//xmlns:bibitem[@id = '#{m[1]}_R1']").to_xml))
    #       .to be_equivalent_to Canon.format_xml(<<~OUTPUT)
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
            identifier: Annex A (normative)  Annex (informative)
          - fileref: test_sectionsplit.html.6.xml
            identifier: Annex B (normative)  Annex 2
          - fileref: test_sectionsplit.html.7.xml
            identifier: Bibliography

      OUTPUT
    FileUtils.rm_f "tmp_test_sectionsplit.presentation.xml"
  end

  it "YAML collection with multiple documents sectionsplit (source document for links)" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                 "action_schemaexpg1.svg"
    file = "#{INPATH}/collection_sectionsplit.yml"
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation html xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
    expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
    expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
    expect(File.exist?("#{INPATH}/ISO_17301-1_2016_index.html")).to be false
    expect(File.exist?("#{OUTPATH}/ISO_17301-1_2016_index.html")).to be true
    expect(File.exist?("#{OUTPATH}/index.html")).to be true
    expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
      .to include "ISO Collection 1"
    expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be false
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be false
    # require 'debug'; binding.b
    expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
      .to be false
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml.0.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml.1.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml.2.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
      .to be true
    expect(File.exist?("#{OUTPATH}/_dummy_attachments/LICENSE1.TXT")).to be true
    rice = File.read("#{OUTPATH}/rice-en.final.xml.1.html")
    expect(rice).to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
    expect(rice).to include %(It is not applicable to cooked rice products, which are not discussed in <a href="rice-en.final.xml.2.html#anotherclause_ISO_17301-1_2016_ISO_17301-1_2016_2_This_is_another_clause"><span class="citesec">Clause 2</span></a> or <a href="rice-en.final.xml.3.html#thirdclause_ISO_17301-1_2016_ISO_17301-1_2016_3_This_is_another_clause"><span class="citesec">Clause 3</span></a>.</p>)
    expect(rice).to include %(<div id=\"_scope_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope\">)
    # resolves SVG references to Express
    expect(rice).to match %r{<a xlink:href="dummy.html#express-schema_E1_ISO_17302">\s+<rect x="324\.69" y="450\.52"}m
    expect(rice).to match %r{<a xlink:href="dummy.html#express-schema_E2_ISO_17302">\s+<rect x="324\.69" y="528\.36"}m
    expect(rice).to match %r{<a xlink:href="mn://action_schema">\s+<rect x="123\.28" y="273\.93"}m
    # demonstrate that erefs are removed if they point to another document in the repository,
    # but that document is not supplied
    expect(rice).to match %r{This document uses schemas E0/A0, <a href="dummy\.html#express-schema_E1_ISO_17302">E1/A1</a> and <a href="dummy\.html#express-schema_E2_ISO_17302">express-schema/E2</a>.}
    expect(rice).to include %(This document is also unrelated to <a href="dummy.html#what">)
    xml = Nokogiri::XML(File.read("#{OUTPATH}/rice-en.final.xml.1.presentation.xml"))
    p = xml.xpath("//xmlns:sections//xmlns:p")[4]
    p.delete("id")
    expect(p.to_xml.gsub(/ (source|id|semx-id)="[^"]+"/, "")).to be_equivalent_to <<~OUTPUT
      <p>This document is updated in <eref type="inline" bibitemid="RiceAmd_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope" citeas="ISO 17301-1:2016/Amd.1:2017"/><semx element="eref"><fmt-link target="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</fmt-link></semx>.</p>
    OUTPUT
    FileUtils.rm_rf of
  end

  it "YAML collection with multiple documents sectionsplit (target document for links)" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                 "action_schemaexpg1.svg"
    file = "#{INPATH}/collection_target_sectionsplit.yml"
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation html xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
    expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
    expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
    expect(File.exist?("#{INPATH}/ISO_17302_2016_index.html")).to be false
    expect(File.exist?("#{OUTPATH}/ISO_17302_2016_index.html")).to be true
    expect(File.exist?("#{OUTPATH}/index.html")).to be true
    expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
      .to include "ISO Collection 1"
    expect(File.exist?("#{OUTPATH}/dummy.html")).to be false
    expect(File.exist?("#{OUTPATH}/dummy.xml")).to be false
    expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be false
    expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
      .to be true
    expect(File.exist?("#{OUTPATH}/dummy.xml.0.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/dummy.xml.1.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/dummy.xml.2.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
      .to be true
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(It is not applicable to cooked rice products, which are not discussed in <a href="#anotherclause_ISO_17301-1_2016"><span class="citesec">Clause 2</span></a> or <a href="#thirdclause_ISO_17301-1_2016"><span class="citesec">Clause 3</span></a>.</p>)
    # demonstrate that erefs are removed if they point to another document in the repository,
    # and point to the right sectionsplit file
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(This document is also unrelated to <a href="dummy.xml.3.html#what">)
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %{This document is also unrelated to <a href="dummy.xml.3.html#what">current-metanorma-collection/ISO 17302:2016 3 What?</a>.</p><p id="_001_ISO_17301-1_2016">This document uses schemas E0/A0, <a href="dummy.xml.2.html#A1_ISO_17302_2016_ISO_17302_2016_2">E1/A1</a> and <a href="dummy.xml.4.html#E2_ISO_17302_2016_ISO_17302_2016_4">E2</a>.</p>}
    FileUtils.rm_rf of
  end

  it "YAML collection with single document sectionsplit" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                 "action_schemaexpg1.svg"
    file = "#{INPATH}/collection_sectionsplit_solo.yml"
    of = File.join(FileUtils.pwd, OUTPATH)
    FileUtils.rm_rf "#{OUTPATH}/index.html"
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation html xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
    expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/ISO_17301-1_2016_index.html")).to be true
    expect(File.exist?("#{OUTPATH}/index.html")).to be true
    expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
      .to include "ISO Collection 1"
    expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be false
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be false
    expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
      .to be false
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml.0.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml.1.html"))
      .to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final.xml.2.html"))
      .to be true
    expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
      .to include %(This document is updated in <b>** Unresolved reference to document ISO 17301-1:2016/Amd.1:2017 from eref</b>.</p>)
    expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
      .to include %(This document uses schemas E0/A0, E1/A1 and express-schema/E2.)
    expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
      .to include %(This document is also unrelated to <a href="dummy.html#what">)
    FileUtils.rm_rf of
  end

  it "deals with footnotes and annotations in section split" do
    mock_uuid_increment
    mock_annotation_body
    file = "#{INPATH}/footnotes.yml"
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse file

    col.render(
      format: %i[presentation html xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    expect(File.exist?("#{OUTPATH}/footnotes.xml.1.html")).to be true
    expect(File.exist?("#{OUTPATH}/footnotes.xml.2.html")).to be true
    expect(File.exist?("#{OUTPATH}/footnotes.xml.3.html")).to be true
    file0 = File.read("#{OUTPATH}/footnotes.xml.1.html")
    file1 = File.read("#{OUTPATH}/footnotes.xml.2.html")
    file2 = File.read("#{OUTPATH}/footnotes.xml.3.html")
    xml0 = Nokogiri::XML(file0)
    xml1 = Nokogiri::XML(file1)
    xml2 = Nokogiri::XML(file2)
    xml = "<xml>#{xml0.xpath('//a[@class = "FootnoteRef"] | //aside').to_xml}</xml>"
    output = <<~OUTPUT
      <xml>
          <a class="FootnoteRef" href="#fn:_97_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1" id="fnref:1">
             <sup>1</sup>
          </a>
          <a class="FootnoteRef" href="#fn:_98_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1" id="fnref:2">
             <sup>2</sup>
          </a>
          <aside id="fn:_97_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1" class="footnote">
             <p id="_">
                <a class="FootnoteRef" href="#fn:_97_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
                   <sup>1</sup>
                </a>
                First footnote
             </p>
             <a href="#fnref:1">↩</a>
          </aside>
          <a class="FootnoteRef" href="#fn:_97_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
             <sup>1</sup>
          </a>
          <aside id="fn:_98_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1" class="footnote">
             <p id="_">
                <a class="FootnoteRef" href="#fn:_98_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
                   <sup>2</sup>
                </a>
                Second footnote
             </p>
             <a href="#fnref:2">↩</a>
          </aside>
          <a class="FootnoteRef" href="#fn:_98_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
             <sup>2</sup>
          </a>
       </xml>
    OUTPUT
    expect(file0).to include("First annotation")
    expect(file0).to include("Second annotation")
    expect(file0).not_to include("Third annotation")
    expect(file0).not_to include("Fourth annotation")
    expect(file0).not_to include("Fifth annotation")
    expect(file0).not_to include("Sixth annotation")

    expect(cleanup_guid(Canon.format_xml(xml)).gsub(/#{GUID}/o, ""))
      .to be_equivalent_to Canon.format_xml(output)
    xml = "<xml>#{xml1.xpath('//a[@class = "FootnoteRef"] | //aside').to_xml}</xml>"
    output = <<~OUTPUT
      <xml>
         <a class="FootnoteRef" href="#fn:_99_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2" id="fnref:1">
            <sup>1</sup>
         </a>
         <a class="FootnoteRef" href="#fn:_100_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2" id="fnref:2">
            <sup>2</sup>
         </a>
         <aside id="fn:_99_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2" class="footnote">
            <p id="_">
               <a class="FootnoteRef" href="#fn:_99_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
                  <sup>1</sup>
               </a>
               Third footnote
            </p>
            <a href="#fnref:1">↩</a>
         </aside>
         <a class="FootnoteRef" href="#fn:_99_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
            <sup>1</sup>
         </a>
         <aside id="fn:_100_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2" class="footnote">
            <p id="_">
               <a class="FootnoteRef" href="#fn:_100_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
                  <sup>2</sup>
               </a>
               Fourth footnote
            </p>
            <a href="#fnref:2">↩</a>
         </aside>
         <a class="FootnoteRef" href="#fn:_100_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
            <sup>2</sup>
         </a>
      </xml>
    OUTPUT
    expect(cleanup_guid(Canon.format_xml(xml)).gsub(/#{GUID}/o, ""))
      .to be_equivalent_to Canon.format_xml(output)
    expect(file1).not_to include("First annotation")
    expect(file1).not_to include("Second annotation")
    expect(file1).to include("Third annotation")
    expect(file1).to include("Fourth annotation")
    expect(file1).not_to include("Fifth annotation")
    expect(file1).not_to include("Sixth annotation")

    xml = "<xml>#{xml2.xpath('//a[@class = "FootnoteRef"] | //aside').to_xml}</xml>"
    output = <<~OUTPUT
      <xml>
         <a class="FootnoteRef" href="#fn:_101_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3" id="fnref:1">
            <sup>1</sup>
         </a>
         <a class="FootnoteRef" href="#fn:_102_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3" id="fnref:2">
            <sup>2</sup>
         </a>
         <aside id="fn:_101_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3" class="footnote">
            <p id="_">
               <a class="FootnoteRef" href="#fn:_101_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
                  <sup>1</sup>
               </a>
               Fifth footnote
            </p>
            <a href="#fnref:1">↩</a>
         </aside>
         <a class="FootnoteRef" href="#fn:_101_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
            <sup>1</sup>
         </a>
         <aside id="fn:_102_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3" class="footnote">
            <p id="_">
               <a class="FootnoteRef" href="#fn:_102_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
                  <sup>2</sup>
               </a>
               Sixth footnote
            </p>
            <a href="#fnref:2">↩</a>
         </aside>
         <a class="FootnoteRef" href="#fn:_102_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
            <sup>2</sup>
         </a>
      </xml>
    OUTPUT
    expect(cleanup_guid(Canon.format_xml(xml)).gsub(/#{GUID}/o, ""))
      .to be_equivalent_to Canon.format_xml(output)
    expect(file2).not_to include("First annotation")
    expect(file2).not_to include("Second annotation")
    expect(file2).not_to include("Third annotation")
    expect(file2).not_to include("Fourth annotation")
    expect(file2).to include("Fifth annotation")
    expect(file2).to include("Sixth annotation")
  end

  private

  def mock_render
    original_add = Metanorma::Collection::Renderer.method(:render)
    allow(Metanorma::Collection::Renderer)
      .to receive(:render) do |col, opts|
      original_add.call(col, opts.merge(compile: { install_fonts: false }))
    end
  end

  def mock_annotation_body
    allow_any_instance_of(::IsoDoc::HtmlConvert)
      .to receive(:comments) do |_instance, docxml, out|
        docxml.xpath("//xmlns:fmt-annotation-body").each do |c|
          c["xmlns"] = nil
          out.parent << c.to_xml
        end
      end
  end
end
