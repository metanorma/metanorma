require_relative "../spec_helper"
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
    Metanorma::Compile.new.compile("spec/fixtures/collection/test_sectionsplit.xml",
                                   type: "iso",
                                   extension_keys: %i[presentation html],
                                   bare: nil,
                                   sectionsplit: "true",
                                   datauriimage: true,
                                   agree_to_terms: true)
    f = "spec/fixtures/collection/test_sectionsplit.html_collection"
    expect(File.exist?("#{f}/index.html")).to be true
    index = File.read("#{f}/index.html")
    expect(index).to include '<a href="test_sectionsplit.html.1.html">'
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
    # isodoc 3.7.21 asset store: the per-document assets dir no longer
    # emits a sidecar cover.html — the section cover renders inline in
    # the first section page (isodoc#920).
    expect(File.read("spec/fixtures/collection/test_sectionsplit.html_collection/test_sectionsplit.html.0.html"))
      .to include('<div class="title-section">')
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
    # isodoc 3.7.21 asset store: the per-document section state yaml no
    # longer emits next to the section pages (isodoc#920).
    m = /type="([^"]+)"/.match(File.read("#{f}/test_sectionsplit.html.0.xml"))
    file2 = Nokogiri::XML(File.read("#{f}/test_sectionsplit.html.3.xml"))
    file2.xpath("//xmlns:emf").each(&:remove)
    expect(file2.at('//xmlns:p[@semx-id = "middletitle"]')).not_to be_nil
    expect(file2.at('//xmlns:note[@semx-id = "middlenote"]')).not_to be_nil
    # isodoc 3.7.21 asset store + the sectionsplit anchor re-keying: ids
    # carry the ___<section> suffix and the hidden bibitems cite the
    # target section pages directly (isodoc#920).
    expect(file2
      .at("//xmlns:fmt-eref[starts-with(@bibitemid, '#{m[1]}_A')]").to_xml.sub(/ id="[^"]+"/, ""))
      .to be_xml_equivalent_to <<~OUTPUT
        <fmt-eref type="#{m[1]}" bibitemid="#{m[1]}_A___Clause_4" citeas="abstract">HE<localityStack><locality type="anchor"><referenceFrom>A_abstract</referenceFrom></locality></localityStack></fmt-eref>
      OUTPUT
    expect(file2
     .at('//xmlns:note[@semx-id = "N1"]//xmlns:fmt-eref')
      .to_xml.sub(/ id="[^"]+"/, ""))
      .to be_xml_equivalent_to <<~OUTPUT
        <fmt-eref type="#{m[1]}" bibitemid="#{m[1]}_R1___Clause_4" citeas="1 Normative References">SHE<localityStack><locality type="anchor"><referenceFrom>R1_1_Normative_References</referenceFrom></locality></localityStack></fmt-eref>
      OUTPUT
    expect(file2
     .at('//xmlns:note[@semx-id = "N2"]//xmlns:fmt-eref')
      .to_xml.sub(/ id="[^"]+"/, ""))
      .to be_xml_equivalent_to <<~OUTPUT
        <fmt-eref type="#{m[1]}" bibitemid="#{m[1]}_R1___Clause_4" citeas="1 Normative References"><image src="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/><localityStack><locality type="anchor"><referenceFrom>R1_1_Normative_References</referenceFrom></locality></localityStack></fmt-eref>
      OUTPUT
    expect(file2
     .at('//xmlns:note[@semx-id = "N3"]//xmlns:fmt-link')
      .to_xml.sub(/ id="[^"]+"/, "").sub(/ id="[^"]+"/, ""))
      .to be_xml_equivalent_to <<~OUTPUT
        <fmt-link attachment="true" target="_test_sectionsplit_attachments/LICENSE.TXT">License A</fmt-link>
      OUTPUT
    expect(file2
      .at("//xmlns:bibitem[@id = 'R1']"))
      .to be_nil
    expect(file2
      .xpath("//xmlns:bibitem").find { |b| b["id"] =~ /_A\z/ }.to_xml)
      .to be_xml_equivalent_to <<~OUTPUT
        <bibitem hidden="true" id="#{m[1]}_A___Clause_4" anchor="#{m[1]}_A___Clause_4">
        <title>ISO Title</title>
        <uri type="citation">test_sectionsplit.html.1.html</uri><docidentifier type="ISO">ISO 1</docidentifier>
        </bibitem>
      OUTPUT
    expect(file2
      .xpath("//xmlns:bibitem").find { |b| b["id"] =~ /_R1\z/ }.to_xml)
      .to be_xml_equivalent_to <<~OUTPUT
        <bibitem hidden="true" id="#{m[1]}_R1___Clause_4" anchor="#{m[1]}_R1___Clause_4">
        <title>ISO Title</title>
        <uri type="citation">test_sectionsplit.html.4.html</uri><docidentifier type="ISO">ISO 1</docidentifier>
        </bibitem>
      OUTPUT
    expect(file2
      .at("//xmlns:svgmap[1]").to_xml.gsub(/ (source|id)="[^"]+"/, ""))
      .to be_xml_equivalent_to <<~OUTPUT
        <svgmap>
           <figure>
           <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" x="0px" y="0px" viewBox="0 0 595.28 841.89" style="enable-background:new 0 0 595.28 841.89;" xml:space="preserve" semx-id="Layer_1_000000000" original-id="Layer_1_000000000" preserveaspectratio="xMidYMin slice">
             <image style="overflow:visible;" width="1" height="1" xlink:href="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/>
             <a href="A">A</a>
             <a href="B">B</a>
           </svg>
           <target href="B"><eref bibitemid="R1___Clause_4" citeas="R1"/><semx element="eref"><fmt-eref type="#{m[1]}" bibitemid="#{m[1]}_R1___Clause_4" citeas="1 Normative References">R1<localityStack><locality type="anchor"><referenceFrom>R1_1_Normative_References</referenceFrom></locality></localityStack></fmt-eref></semx></target>
         </figure>
         <target href="A"><eref type="#{m[1]}" bibitemid="#{m[1]}_A___Clause_4" citeas="abstract">A<localityStack><locality type="anchor"><referenceFrom>A_abstract</referenceFrom></locality></localityStack></eref></target><target href="B"><eref type="#{m[1]}" bibitemid="#{m[1]}_B___Clause_4" citeas="introduction">B<localityStack><locality type="anchor"><referenceFrom>B_introduction</referenceFrom></locality></localityStack></eref></target></svgmap>
      OUTPUT
    expect(file2
     .at("//xmlns:svgmap[2]").to_xml.gsub(/ (source|id)="[^"]+"/, ""))
      .to be_xml_equivalent_to <<~OUTPUT
        <svgmap>
  <figure>
           <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" x="0px" y="0px" viewBox="0 0 595.28 841.89" style="enable-background:new 0 0 595.28 841.89;" xml:space="preserve" semx-id="Layer_1_000000000___Clause_4_000000002" preserveaspectratio="xMidYMin slice" original-id="Layer_1_000000000___Clause_4_000000002">
           <image style="overflow:visible;" width="1" height="1" xlink:href="data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7"/>
           <a href="P">P</a>
         </svg>
         </figure>
  <target href="P">
    <eref type="#{m[1]}" bibitemid="#{m[1]}_P___Clause_4" citeas="Annex A (normative) Annex (informative)">P<localityStack><locality type="anchor"><referenceFrom>P_Annex_A__normative__Annex__informative_</referenceFrom></locality></localityStack></eref>
  </target>
</svgmap>
      OUTPUT
    expect(file2.at("//xmlns:preface")).to be_nil
    expect(file2.at("//xmlns:sections/xmlns:clause")).not_to be_nil
    expect(file2.at("//xmlns:annex")).to be_nil
    expect(file2.at("//xmlns:indexsect")).to be_nil
    FileUtils.rm_f "tmp_test_sectionsplit.presentation.xml"
  end

  it "processes output filename customisation on section split HTML" do
    FileUtils.rm_rf "test_collection"
    FileUtils.rm_rf "test_files"
    f = "spec/fixtures/collection/test_sectionsplit.html_collection"
    FileUtils.rm_rf "#{f}/index.html"
    # require "debug"; binding.b
    FileUtils.rm_rf Dir.glob("#{f}/test_sectionsplit.html.*.html")
    expect(File.exist?("#{f}/index.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.0.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.1.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.2.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.3.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.4.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.5.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.6.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.7.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.8.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.9.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.10.html")).to be false

    mock_render
    Metanorma::Compile.new.compile("spec/fixtures/collection/test_sectionsplit.xml",
                                   type: "iso",
                                   extension_keys: %i[presentation html],
                                   bare: nil,
                                   sectionsplit: "true",
                                   sectionsplit_filename: "file_{basename}_{document-num}_{sectionsplit-num}",
                                   datauriimage: true,
                                   agree_to_terms: true)
    f = "spec/fixtures/collection/test_sectionsplit.html_collection"
    expect(File.exist?("#{f}/index.html")).to be true
    index = File.read("#{f}/index.html")
    expect(index).not_to include '<a href="test_sectionsplit.html.1.html">'
    expect(index).to include '<a href="file_test_sectionsplit_0_1.html">'
    expect(File.exist?("#{f}/test_sectionsplit.html.0.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.1.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.2.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.3.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.4.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.5.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.6.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.7.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.8.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.9.html")).to be false
    expect(File.exist?("#{f}/test_sectionsplit.html.10.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_0.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_1.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_2.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_3.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_4.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_5.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_6.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_7.html")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_8.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_9.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_10.html")).to be false

    expect(File.exist?("#{f}/_test_sectionsplit_attachments/LICENSE.TXT")).to be true
    # isodoc 3.7.21 asset store: the per-document assets dir no longer
    # emits a sidecar cover.html — the section cover renders inline in
    # the first section page (isodoc#920).
    expect(File.read("spec/fixtures/collection/test_sectionsplit.html_collection/test_sectionsplit.html.0.html"))
      .to include('<div class="title-section">')

    expect(File.exist?("#{f}/file_test_sectionsplit_0_0.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_1.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_2.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_3.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_4.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_5.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_6.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_7.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_8.xml")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_9.xml")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_10.xml")).to be false
    # isodoc 3.7.21 asset store: the per-document section state yaml no
    # longer emits next to the section pages (isodoc#920).

    # Clean up for next test - remove both collection and _files directories
    FileUtils.rm_rf "spec/fixtures/collection/test_sectionsplit.html_collection"
    FileUtils.rm_rf Dir.glob("spec/fixtures/collection/test_sectionsplit_*_files")
  end

  it "processes directories for output filename customisation on section split HTML" do
    FileUtils.rm_rf "test_collection"
    FileUtils.rm_rf "test_files"
    # Clean up both the collection directory and the _files directory completely
    FileUtils.rm_rf "spec/fixtures/collection/test_sectionsplit.html_collection"
    FileUtils.rm_rf Dir.glob("spec/fixtures/collection/test_sectionsplit_*_files")
    f = "spec/fixtures/collection/test_sectionsplit.html_collection"
    mock_render
    Metanorma::Compile.new.compile("spec/fixtures/collection/test_sectionsplit.xml",
                                   type: "iso",
                                   extension_keys: %i[presentation html],
                                   bare: nil,
                                   sectionsplit: "true",
                                   sectionsplit_filename: "outdir/file_{basename}_{document-num}_{sectionsplit-num}",
                                   datauriimage: true,
                                   agree_to_terms: true)
    expect(File.exist?("#{f}/index.html")).to be true
    index = File.read("#{f}/index.html")
    expect(index).not_to include '<a href="file_test_sectionsplit_0_1.html">'
    expect(index).to include '<a href="outdir/file_test_sectionsplit_0_1.html">'
    expect(File.exist?("#{f}/file_test_sectionsplit_0_0.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_1.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_2.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_3.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_4.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_5.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_6.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_7.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_8.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_9.html")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_10.html")).to be false
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_0.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_1.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_2.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_3.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_4.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_5.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_6.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_7.html")).to be true
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_8.html")).to be false
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_9.html")).to be false
    expect(File.exist?("#{f}/outdir/file_test_sectionsplit_0_10.html")).to be false

    expect(File.exist?("#{f}/_test_sectionsplit_attachments/LICENSE.TXT")).to be true
    # isodoc 3.7.21 asset store: the per-document assets dir no longer
    # emits a sidecar cover.html — the section cover renders inline in
    # the first section page (isodoc#920).
    expect(File.read("#{f}/outdir/file_test_sectionsplit_0_0.html"))
      .to include('<div class="title-section">')

    expect(File.exist?("#{f}/file_test_sectionsplit_0_0.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_1.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_2.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_3.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_4.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_5.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_6.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_7.xml")).to be true
    expect(File.exist?("#{f}/file_test_sectionsplit_0_8.xml")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_9.xml")).to be false
    expect(File.exist?("#{f}/file_test_sectionsplit_0_10.xml")).to be false
    # isodoc 3.7.21 asset store: the per-document section state yaml no
    # longer emits next to the section pages (isodoc#920).
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
    expect(rice).to include %(This document is updated in <a href="rice-amd.final.html">ISO 17301-1:2016/Amd.1:2017</a>)
    expect(rice).to include %(It is not applicable to cooked rice products, which are not discussed in <a href="rice-en.final.xml.2.html#anotherclause_ISO_17301-1_2016_ISO_17301-1_2016_2_This_is_another_clause"><span class="citesec">Clause 2</span></a> or <a href="rice-en.final.xml.3.html#thirdclause_ISO_17301-1_2016_ISO_17301-1_2016_3_This_is_another_clause"><span class="citesec">Clause 3</span></a>.</p>)
    expect(rice).to include %(<div id=\"_scope_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope\">)
    # resolves SVG references to Express
    expect(rice).to match %r{<a xlink:href="dummy.html#E1_ISO_17302">\s+<rect x="324\.69" y="450\.52"}m
    expect(rice).to match %r{<a xlink:href="dummy.html#E2_ISO_17302">\s+<rect x="324\.69" y="528\.36"}m
    expect(rice).to match %r{<a xlink:href="mn://action_schema">\s+<rect x="123\.28" y="273\.93"}m
    # demonstrate that erefs are removed if they point to another document in the repository,
    # but that document is not supplied
    expect(rice).to match %r{This document uses schemas E0/A0, <a href="dummy.html#E1_ISO_17302">E1/A1</a> and <a href="dummy.html#E2_ISO_17302">express-schema/E2</a> as well as express-schema/E0}
    expect(rice).to include %(This document is also unrelated to <a href="dummy.html#what">)
    xml = Nokogiri::XML(File.read("#{OUTPATH}/rice-en.final.xml.1.presentation.xml"))
    p = xml.xpath("//xmlns:sections//xmlns:p")[4]
    p.delete("id")
    expect(p.to_xml.gsub(/ (source|id|semx-id)="[^"]+"/, "")).to be_xml_equivalent_to <<~OUTPUT
      <p>This document is updated in <eref type="inline" bibitemid="RiceAmd_ISO_17301-1_2016_ISO_17301-1_2016_1_Scope" citeas="ISO 17301-1:2016/Amd.1:2017"/><semx element="eref"><fmt-link target="rice-amd.final.html">ISO 17301-1:2016/Amd.1:2017</fmt-link></semx>.</p>
    OUTPUT
    FileUtils.rm_rf of
  end

  it "YAML collection with multiple documents sectionsplit, document renaming" do
    FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                 "action_schemaexpg1.svg"
    file = "#{INPATH}/collection_sectionsplit_rename.yml"
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

    # Test collection-level files
    expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
    expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/ISO_17301-1_2016_index.html")).to be true
    expect(File.exist?("#{OUTPATH}/index.html")).to be true
    expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
      .to include "ISO Collection 1"

    # Test rice-en.final (document 0, sectionsplit enabled)
    # HTML files go to d0/ subdirectory
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_0.html")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_1.html")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_2.html")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_3.html")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_4.html")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_5.html")).to be true

    # Presentation.xml files go to d0/ subdirectory
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_0.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_1.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_2.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_3.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_4.presentation.xml")).to be true
    expect(File.exist?("#{OUTPATH}/d0/rice-en.final_5.presentation.xml")).to be true

    # XML files stay in root (by design for sectionsplit)
    expect(File.exist?("#{OUTPATH}/rice-en.final_0.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_1.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_2.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_3.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_4.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_5.xml")).to be true

    # Error HTML files stay in root
    expect(File.exist?("#{OUTPATH}/rice-en.final_0.err.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_1.err.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_2.err.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_3.err.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_4.err.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-en.final_5.err.html")).to be true

    # Test dummy (document 1, no sectionsplit) - generates regular files, not split
    expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true

    # Test rice1-en.final (document 2, no sectionsplit) - generates regular files, not split
    expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml")).to be true

    # Test rice-amd.final (document 3, no sectionsplit) - generates regular files, not split
    expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
    expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml")).to be true

    # Test attachments
    expect(File.exist?("#{OUTPATH}/_dummy_attachments/LICENSE1.TXT")).to be true

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
      .to include %(This document is updated in <a href="rice-amd.final.html">ISO 17301-1:2016/Amd.1:2017</a>)
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(It is not applicable to cooked rice products, which are not discussed in <a href="#anotherclause_ISO_17301-1_2016"><span class="citesec">Clause 2</span></a> or <a href="#thirdclause_ISO_17301-1_2016"><span class="citesec">Clause 3</span></a>.</p>)
    # demonstrate that erefs are removed if they point to another document in the repository,
    # and point to the right sectionsplit file
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %(This document is also unrelated to <a href="dummy.xml.3.html#what">)
    expect(File.read("#{OUTPATH}/rice-en.final.html"))
      .to include %{This document is also unrelated to <a href="dummy.xml.3.html#what"><span class="stdpublisher">current-metanorma-collection/ISO</span> <span class="stddocNumber">17302</span>:<span class="stdyear">2016</span> 3 What?</a>.</p><p id="_001_ISO_17301-1_2016">This document uses schemas <a href="#express-schema_E0_ISO_17301-1_2016">E0/A0</a>, <a href="dummy.xml.2.html#A1_ISO_17302_2016_ISO_17302_2016_2">E1/A1</a> and <a href="dummy.xml.4.html#E2_ISO_17302_2016_ISO_17302_2016_4">E2</a> as well as <a href="#express-schema_E0_ISO_17301-1_2016"><span class="stdpublisher">metanorma-collection</span> Missing:express-schema:E<span class="stddocNumber">0</span> / current-metanorma-collection/Missing:express-schema:E0</a>.}
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
      .to include %(This document uses schemas E0/A0, E1/A1 and express-schema/E2 as well as express-schema/E0)
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
    xml, base0 = normalize_footnote_anchor_nums(xml)
    output = <<~OUTPUT
         <xml>
          <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1" id="fnref:1">
             <sup>1)</sup>
           </a>
          <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1" id="fnref:2">
             <sup>2)</sup>
           </a>
          <aside class="footnote" id="fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
             <p id="_">
              <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
                 <sup>1)</sup>
               </a>
               First footnote
             </p>
             <a href="#fnref:1">↩</a>
           </aside>
          <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
             <sup>1)</sup>
           </a>
          <aside class="footnote" id="fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
             <p id="_">
              <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
                 <sup>2)</sup>
               </a>
               Second footnote
             </p>
             <a href="#fnref:2">↩</a>
           </aside>
          <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_1_Clause_1">
             <sup>2)</sup>
           </a>
         </xml>
    OUTPUT
    expect(file0).to include("First annotation")
    expect(file0).to include("Second annotation")
    expect(file0).not_to include("Third annotation")
    expect(file0).not_to include("Fourth annotation")
    expect(file0).not_to include("Fifth annotation")
    expect(file0).not_to include("Sixth annotation")

    expect(cleanup_guid(xml).gsub(/#{GUID}/o, ""))
      .to be_xml_equivalent_to output
    xml = "<xml>#{xml1.xpath('//a[@class = "FootnoteRef"] | //aside').to_xml}</xml>"
    xml, base1 = normalize_footnote_anchor_nums(xml)
    output = <<~OUTPUT
         <xml>
          <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2" id="fnref:1">
             <sup>3)</sup>
           </a>
          <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2" id="fnref:2">
             <sup>4)</sup>
           </a>
          <aside class="footnote" id="fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
             <p id="_">
              <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
                 <sup>3)</sup>
               </a>
               Third footnote
             </p>
             <a href="#fnref:1">↩</a>
           </aside>
          <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
             <sup>3)</sup>
           </a>
          <aside class="footnote" id="fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
             <p id="_">
              <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
                 <sup>4)</sup>
               </a>
               Fourth footnote
             </p>
             <a href="#fnref:2">↩</a>
           </aside>
          <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_2_Clause_2">
             <sup>4)</sup>
           </a>
         </xml>
    OUTPUT
    expect(cleanup_guid(xml).gsub(/#{GUID}/o, ""))
      .to be_xml_equivalent_to output
    expect(base1).to be > base0
    expect(file1).not_to include("First annotation")
    expect(file1).not_to include("Second annotation")
    expect(file1).to include("Third annotation")
    expect(file1).to include("Fourth annotation")
    expect(file1).not_to include("Fifth annotation")
    expect(file1).not_to include("Sixth annotation")

    xml = "<xml>#{xml2.xpath('//a[@class = "FootnoteRef"] | //aside').to_xml}</xml>"
    xml, base2 = normalize_footnote_anchor_nums(xml)
    output = <<~OUTPUT
         <xml>
          <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3" id="fnref:1">
             <sup>5)</sup>
           </a>
          <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3" id="fnref:2">
             <sup>6)</sup>
           </a>
          <aside class="footnote" id="fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
             <p id="_">
              <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
                 <sup>5)</sup>
               </a>
               Fifth footnote
             </p>
             <a href="#fnref:1">↩</a>
           </aside>
          <a class="FootnoteRef" href="#fn:_FN1_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
             <sup>5)</sup>
           </a>
          <aside class="footnote" id="fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
             <p id="_">
              <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
                 <sup>6)</sup>
               </a>
               Sixth footnote
             </p>
             <a href="#fnref:2">↩</a>
           </aside>
          <a class="FootnoteRef" href="#fn:_FN2_ISO_17301-1_2016_ISO_17301-1_2016_3_Clause_3">
             <sup>6)</sup>
           </a>
         </xml>
    OUTPUT
    expect(cleanup_guid(xml).gsub(/#{GUID}/o, ""))
      .to be_xml_equivalent_to output
    expect(base2).to be > base1
    expect(file2).not_to include("First annotation")
    expect(file2).not_to include("Second annotation")
    expect(file2).not_to include("Third annotation")
    expect(file2).not_to include("Fourth annotation")
    expect(file2).to include("Fifth annotation")
    expect(file2).to include("Sixth annotation")
  end

  private

  # Section-split footnote body anchors are "fn:_<num>_<docid>_<docid>_<n>
  # _Clause_<n>": <num> is the value of the sequential identifier counter
  # when isodoc assigned the footnote body id. That counter value is not
  # stable across run contexts or gem versions: the same working tree
  # yields _98 when this example runs alone and _93 when the whole file
  # runs, because the number of identifier draws upstream of the footnote
  # assignment (FileLookup#read_anchors UUID keys for label-less anchors,
  # generated clause/TOC ids) shifts with warmed process state
  # (metanorma#644). What IS stable, and what this spec pins: exactly two
  # anchors per split file, numbered consecutively in footnote order, and
  # strictly increasing across the split files. Normalize the volatile
  # numbers to positional tokens (FN1, FN2) and return the file's first
  # number for the cross-file monotonicity check.
  def normalize_footnote_anchor_nums(xml)
    nums = xml.scan(/fn:_(\d+)_/).flatten.map(&:to_i).uniq.sort
    expect(nums.size).to eq(2)
    expect(nums.last).to eq(nums.first + 1)
    subs = nums.each_with_index.to_h { |n, i| [n, "FN#{i + 1}"] }
    [xml.gsub(/fn:_(\d+)_/) { "fn:_#{subs[Regexp.last_match[1].to_i]}_" },
     nums.first]
  end

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
