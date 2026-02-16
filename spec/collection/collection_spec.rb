# frozen_string_literal: true

require_relative "../spec_helper"
require "stringio"

def capture_stdout
  old = $stdout
  $stdout = fake = StringIO.new
  yield
  fake.string
ensure
  $stdout = old
end

INPATH = "spec/fixtures/collection"
OUTPATH = "spec/fixtures/output"

RSpec.describe Metanorma::Collection do
  context "parse" do
    it "YAML collection manifest to YAML" do
      mock_pdf
      mc = Metanorma::Collection.parse "#{INPATH}/collection1.yml"
      expect(mc).to be_instance_of Metanorma::Collection
      yaml_out = mc.config.to_yaml
        .gsub(/identifier: ['"]?#{GUID}['"]?[\n\r]+\s*/mo, "\\1")
        .gsub(/([\n\r]+\s+)schema-version: \S+[\n\r]+\s*/m, "\\1")
      expect(yaml_out).to be_equivalent_to <<~OUTPUT
        ---
        directives:
        - documents-external:
        - coverpage: collection_cover.html
        - coverpage-pdf-portfolio: cover.pdf
        - keystore-pdf-portfolio: keystore.p12
        - keystore-password-pdf-portfolio: '123456'
        bibdata:
          id: ISO12345
          title:
          - content: ISO Collection 1
            language:
            - en
            format: text/plain
            type: title-main
          type: collection
          docid:
          - id: ISO 12345
            type: iso
            primary: 'true'
          date:
          - type: created
            value: '2020'
          - type: issued
            value: '2020'
          edition:
            content: '1'
          copyright:
          - owner:
            - name:
              - content: International Organization for Standardization
              abbreviation:
                content: ISO
            from: '2020'
        manifest:
          type: collection
          title: ISO Collection
          index: true
          entry:
          - type: subcollection
            title: Standards
            index: true
            entry:
            - identifier: ISO 17301-1:2016
              pdf-file: rice17301.pdf
              index: true
              file: rice-en.final.xml
              bibdata:
              sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
            - identifier: ISO 17302:2016
              url: example/url
              index: true
              file: dummy.xml
              bibdata:
              sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
            - identifier: ISO 1701:1974
              index: true
              file: rice1-en.final.xml
              bibdata:
              sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
            bibdata:
            sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
          - type: subcollection
            title: Amendments
            index: true
            entry:
              identifier: ISO 17301-1:2016/Amd.1:2017
              index: true
              file: rice-amd.final.xml
              bibdata:
              sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
            bibdata:
            sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
          - type: attachments
            title: Attachments
            index: true
            entry:
            - identifier: action_schemaexpg1.svg
              attachment: true
              index: true
              file: pics/action_schemaexpg1.svg
              bibdata:
              sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
            - identifier: rice_image1.png
              attachment: true
              index: true
              file: "../../assets/rice_image1.png"
              bibdata:
              sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
            bibdata:
            sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
          bibdata:
          sectionsplit-filename: "{basename_legacy}.{sectionsplit-num}"
        format:
        - html
        coverpage: cover.html
        prefatory-content: |2

          == Clause
          Welcome to our collection
        final-content: |2

          == Exordium
          Hic explicit
      OUTPUT
    end

    it "YAML collection to XML" do
      mock_pdf
      xml_file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(Canon.format_xml(cleanup_guid(xml))))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(xml_content))
    end

    it "YAML collection with no document identifiers" do
      mock_pdf
      xml_file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1noid.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(Canon.format_xml(cleanup_guid(xml))))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(xml_content))
    end

    it "YAML collection with docs inline" do
      mock_pdf
      xml_file = "#{INPATH}/collection_docinline.xml"
      mc = Metanorma::Collection
        .parse("#{INPATH}/collection_docinline.yml")
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      expect(Canon.format_xml(cleanup_guid(cleanup_id(xml))))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(read_and_cleanup(xml_file)))

      newyaml = "#{INPATH}/collection_docinline1.yml"
      File.open newyaml, "w" do |f|
        f.write(File.read("#{INPATH}/collection_docinline.yml")
          .sub(/- documents-inline/, ""))
      end
      mc = Metanorma::Collection.parse(newyaml)
      xml = mc.to_xml
      FileUtils.rm_rf newyaml
      expect(Canon.format_xml(cleanup_guid(cleanup_id(xml))))
        .to be_equivalent_to Canon.format_xml(cleanup_guid(read_and_cleanup(xml_file)))
    end

    it "YAML collection with interleaved documents and manifests" do
      mock_pdf
      xml_file = "#{INPATH}/collection1nested.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1nested.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(Canon.format_xml(cleanup_id(xml)))
        .to be_equivalent_to Canon.format_xml(xml_content)
    end

    context "YAML collection with new format" do
      let(:yaml_file) { "#{INPATH}/collection_new.yml" }
      let(:ccm) do
        Metanorma::Collection.parse(yaml_file).manifest
          .to_xml(Nokogiri::XML::Builder.new).to_xml
      end

      describe "when constructing collection manifest" do
        it "should inherit sectionsplit and have correct format" do
          expect(Canon.format_xml(cleanup_id(ccm)))
            .to be_equivalent_to Canon.format_xml(cleanup_id(<<~OUTPUT))
              <entry index="true">
                <identifier>27b4fbb3-a76e-42c9-a519-3cf18a7ca1c5</identifier>
                <type>collection</type>
                <title>ISO Collection</title>
                <entry index="true">
                  <identifier>00b50518-1656-465e-b14a-ba4e67aff9d0</identifier>
                  <entry index="true">
                    <identifier>4409d72f-9e2d-4aa3-bc3f-732ba76e211c</identifier>
                    <type>collection</type>
                    <title>ISO Collection</title>
                    <entry index="true">
                      <identifier>5a254d10-6c28-4721-872e-4974dfc035a3</identifier>
                      <type>document</type>
                      <title>Document</title>
                      <entry target="doc000000000" sectionsplit="true" index="true" fileref="document-1/document-1.xml">
                        <identifier>ISO 12345-1:2024</identifier>
                      </entry>
                    </entry>
                    <entry index="true">
                      <identifier>eb779c1d-f770-47e4-9d5f-83958e59be0f</identifier>
                      <type>attachments</type>
                      <title>Attachments</title>
                      <entry target="doc000000001" attachment="true" index="true" fileref="document-1/img/action_schemaexpg2.svg">
                        <identifier>action_schemaexpg2.svg</identifier>
                      </entry>
                      <entry target="doc000000002" attachment="true" index="true" fileref="../../assets/rice_image1.png">
                        <identifier>rice_image1.png</identifier>
                      </entry>
                    </entry>
                  </entry>
                </entry>
                <entry index="true">
                  <identifier>fcd781f4-4189-407d-b316-eb676fd04cb9</identifier>
                  <entry index="true">
                    <identifier>67ae8932-3c18-4ff1-987f-b0cb7093f460</identifier>
                    <type>collection</type>
                    <title>ISO Collection</title>
                    <entry index="true">
                      <identifier>862b2f9e-0e7a-4a01-9916-27500e141a46</identifier>
                      <type>document</type>
                      <title>Document</title>
                      <entry target="doc000000003" sectionsplit="true" index="true" fileref="document-2/document-2.xml">
                        <identifier>ISO 12345-2:2024</identifier>
                      </entry>
                    </entry>
                    <entry index="true">
                      <identifier>380c7f48-59e5-44c8-b5db-5ac5d79c12f3</identifier>
                      <type>attachments</type>
                      <title>Attachments</title>
                      <entry target="doc000000004" attachment="true" index="true" fileref="document-2/img/action_schemaexpg3.svg">
                        <identifier>action_schemaexpg3.svg</identifier>
                      </entry>
                       <entry target="doc000000005" attachment="true" index="true" fileref="document-2/img/action_schemaexpg3.svg">
                      <identifier>action_schemaexpg3bis.svg</identifier>
                   </entry>
                    </entry>
                  </entry>
                </entry>
              </entry>
          OUTPUT
        end

        it "should allow user to set identifier" do
          my_identifier_proc = Proc.new do |identifier|
            identifier = case identifier
                         when "action_schemaexpg2.svg"
                           "freedom"
                         else
                           identifier
                         end
            next identifier
          end
          Metanorma::Collection.set_identifier_resolver(&my_identifier_proc)
          xml = Nokogiri::XML(ccm)
          id = xml.at("//entry[@fileref = 'document-1/img/" \
                      "action_schemaexpg2.svg']/identifier")
          expect(id.text).to eq "freedom"
          id = xml.at("//entry[@fileref = 'document-2/img/" \
                      "action_schemaexpg3.svg']/identifier")
          expect(id.text).to eq "action_schemaexpg3.svg"
          id = xml.at("//entry[@fileref = '../../assets/" \
                      "rice_image1.png']/identifier")
          expect(id.text).to eq "rice_image1.png"
        end

        it "should allow user to point fileref to new location conditionally" do
          my_fileref_proc = Proc.new do |ref_folder, fileref|
            if fileref == "document-1/img/action_schemaexpg2.svg"
              fileref = fileref.gsub("img/", "image/")
            end
            fileref = File.join(ref_folder, fileref)
            next fileref
          end
          Metanorma::Collection.set_fileref_resolver(&my_fileref_proc)
          xml = Nokogiri::XML(ccm)
          id = xml.at("//entry[@target = 'doc000000001']/@fileref")
          expect(id.text).to eq "document-1/image/action_schemaexpg2.svg"
        end
      end

      describe "when parsing and rendering model" do
        let(:parse_model) { Metanorma::Collection.parse(yaml_file) }
        let(:collection_opts) do
          {
            format: [:html],
            output_folder: File.join(FileUtils.pwd, OUTPATH),
            compile: {
              install_fonts: false,
            },
            coverpage: "cover1.html",
          }
        end

        let(:compile_adoc) do
          Metanorma::Collection.send(
            :compile_adoc_documents,
            collection_model,
          )
        end

        before do
          my_identifier_proc = Proc.new do |identifier|
            identifier = case identifier
                         when /^spec\/fixtures\/collection\//
                           identifier.gsub("spec/fixtures/collection/", "")
                         else
                           identifier
                         end
            next identifier
          end

          Metanorma::Collection.set_identifier_resolver(&my_identifier_proc)
        end

        it "should allow user to define a proc to run" do
          my_proc = Proc.new { puts "Test Proc!" }
          Metanorma::Collection.unset_fileref_resolver
          Metanorma::Collection.set_pre_parse_model(&my_proc)
          printed = capture_stdout do
            Metanorma::Collection.send(:pre_parse_model, parse_model)
          end
          expect(printed).to include("Test Proc!")
        end

        it "should raise error if adoc files not found" do
          my_dumb_fileref_proc = Proc.new do |ref_folder, fileref|
            /\.adoc$?/.match?(fileref) and fileref = "dunno/#{fileref}"
            fileref = File.join(ref_folder, fileref)
            next fileref
          end

          Metanorma::Collection.set_fileref_resolver(&my_dumb_fileref_proc)

          expect { parse_model.render(collection_opts) }.to raise_error(
            Metanorma::AdocFileNotFoundException, /document-1\.adoc not found!/
          )
        end

        it "should raise error if YAML files not found" do
          my_dumb_fileref_proc = Proc.new do |ref_folder, fileref|
            /\.ya?ml$?/.match?(fileref) and fileref = "dunno/#{fileref}"
            fileref = File.join(ref_folder, fileref)
            next fileref
          end

          Metanorma::Collection.set_fileref_resolver(&my_dumb_fileref_proc)

          expect { parse_model.render(collection_opts) }.to raise_error(
            Metanorma::FileNotFoundException,
            /document-1\/collection\.yml not found!/,
          )
        end

        it "should compile adoc files and return Metanorma::Collection" do
          Metanorma::Collection.unset_fileref_resolver
          xml_paths = [
            "#{INPATH}/document-1/document-1.xml",
            "#{INPATH}/document-2/document-2.xml",
          ]
          xml_paths.each do |x|
            FileUtils.rm_rf(x)
            expect(File.exist?(x)).to be_falsy
          end
          expect(parse_model).to be_instance_of Metanorma::Collection
          xml_paths.each do |x|
            expect(File.exist?(x)).to be_truthy
          end
        end

        it "should render output" do
          Metanorma::Collection.unset_fileref_resolver
          parse_model.render(collection_opts)

          expected_output = {
            "index.html" => "Cover bibdata - Test Title",
            "ISO_12345-1_2024_index.html" => "ISO 12345-1",
            "ISO_12345-2_2024_index.html" => "ISO 12345-2",
          }
          generated_files = Dir["#{OUTPATH}/*"]

          expected_output.each do |k, v|
            expect(generated_files).to include("#{OUTPATH}/#{k}")
            expect(File.read("#{OUTPATH}/#{k}", encoding: "utf-8"))
              .to include(v)
          end
          FileUtils.rm_f("tmp_document-2.presentation.xml")
        end
      end
    end

    it "XML collection" do
      mock_pdf
      file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(cleanup_id(Canon.format_xml(mc.to_xml)))
        .to be_equivalent_to Canon.format_xml(xml)
    end

    it "XML collection with interleaved documents and manifests" do
      mock_pdf
      file = "#{INPATH}/collection1nested.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
    end

    it "XML collection with docs inline" do
      mock_pdf
      file = "#{INPATH}/collection_docinline.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(Canon.format_xml(cleanup_id(mc.to_xml)))
        .to be_equivalent_to Canon.format_xml(xml)
    end
  end

  it "disambiguates destination filenames" do
    file = "#{INPATH}/collection.dup.yml"
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.1.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.2.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.1.html")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.2.html")).to be true
    FileUtils.rm_rf of
  end

  it "skips indexing of files in coverpage on request" do
    file = "#{INPATH}/collection.dup.yml"
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    index = File.read("#{OUTPATH}/index.html")
    expect(index).to include "ISO&nbsp;44001"
    expect(index).not_to include "ISO&nbsp;44002"
    expect(index).to include "ISO&nbsp;44003"
    FileUtils.rm_rf of
  end

  it "inject repository identifiers; leave SVG in logos alone" do
    Dir.chdir("spec")
    file = "../#{INPATH}/collection1.norepo.yml"
    of = File.join(FileUtils.pwd, "../#{OUTPATH}")
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: {
        install_fonts: false,
      },
    )
    Dir.chdir("..")
    index = File.read("#{OUTPATH}/rice-en.final.norepo.xml")
    expect(index).to include "Mass fraction of extraneous matter, milled rice " \
                             "(nonglutinous), sample dividers and " \
                             "recommendations relating to storage and " \
                             "transport conditions"
    # has successfully mapped identifier of ISO 17301-1:2016/Amd.1:2017 in
    # rice-en.final.norepo.xml to the file in the collection,
    # and imported its bibdata
    expect(index).to include 'style="fill:#0f3c80;"' # from SVG logo
    FileUtils.rm_rf of
  end

  it "processes flavor directive" do
    Dir.chdir("spec")
    yaml = File.read "../#{INPATH}/collection_solo.yml"
    of = File.join(FileUtils.pwd, "../#{OUTPATH}")
    newyaml = "../#{INPATH}/collection_new1.yml"
    isostring = "ISO and IEC maintain terminology databases for use in standardization"
    File.open(newyaml, "w") { |x| x.write(yaml) }
    col = Metanorma::Collection.parse newyaml
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
    )
    # manifest docid has docid type iso
    expect(File.read("#{of}/collection.xml"))
      .to include(isostring)

    File.open(newyaml, "w") do |x|
      x.write(yaml.sub("  - documents-inline",
                       "  - documents-inline\n  - flavor: standoc"))
    end
    col = Metanorma::Collection.parse newyaml
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
    )
    expect(File.read("#{of}/collection.xml"))
      .not_to include(isostring)

    File.open(newyaml, "w") do |x|
      x.write(yaml.sub("  - documents-inline",
                       "  - documents-inline\n  - flavor: iso")
        .sub("type: iso", "type: fred"))
    end
    # get flavor from directive not docid
    col = Metanorma::Collection.parse newyaml
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
    )
    expect(File.read("#{of}/collection.xml"))
      .to include(isostring)

    File.open(newyaml, "w") do |x|
      x.write(yaml.sub("  - documents-inline",
                       "  - documents-inline\n  - flavor: oiml")
        .sub("type: iso", "type: fred"))
    end
    # derive flavor from taste
    col = Metanorma::Collection.parse newyaml
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: { install_fonts: false },
    )
    expect(File.read("#{of}/collection.xml"))
      .to include(isostring)

    File.open(newyaml, "w") { |x| x.write(yaml.sub("type: iso", "type: fred")) }
    # ignorable flavor from docid
    col = Metanorma::Collection.parse newyaml
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "collection_cover.html",
      compile: { install_fonts: true, agree_to_terms: true },
    )
    expect(File.read("#{of}/collection.xml"))
      .not_to include(isostring)

    File.open(newyaml, "w") do |x|
      x.write(yaml.sub("  - documents-inline",
                       "  - documents-inline\n  - flavor: fred"))
    end
    begin
      expect do
        Metanorma::Collection.parse newyaml
      end.to raise_error(SystemExit)
    rescue SystemExit, RuntimeError
    end

    FileUtils.rm_rf of
  end

  it "uses local bibdata, preface in prefatory content if needed" do
    #system 'fontist install "Source Serif Pro" --accept-all-licenses'
    #system 'fontist install "STKaiti" --accept-all-licenses'
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse "#{INPATH}/collection-iho.yml"
    col.render(
      format: %i[html presentation xml],
      output_folder: of,
      coverpage: "cover-iho.html",
      compile: { install_fonts: true, agree_to_terms: true },
    )
    # manifest docid has docid type iso
    index = File.read("#{of}/index.html")
    expect(index)
      .to include("Changes to this Specification are coordinated by the IHO S-100 Working Group")
    expect(index)
      .to include("IHO S-97 IHO Guidelines")
    expect(index)
      .to include("S-100WG")
  end

  it "extract custom fonts from collection XML for PDF" do
    mock_pdf
    system 'fontist install "Source Serif Pro" --accept-all-licenses'
    system 'fontist install "STKaiti" --accept-all-licenses'
    of = File.join(FileUtils.pwd, OUTPATH)
    col = Metanorma::Collection.parse "#{INPATH}/collection-iho.yml"
    renderer = nil
    allow(Metanorma::Collection::Renderer)
      .to receive(:new)
      .and_wrap_original do |orig, *args|
        renderer = orig.call(*args)
        allow(renderer).to receive(:pdfconv).and_call_original
        renderer
    end

    col.render(
      format: %i[pdf presentation xml],
      output_folder: of,
      coverpage: "cover-iho.html",
      compile: { install_fonts: false },
    )
    expect(renderer)
      .to have_received(:pdfconv)
      .with(hash_including(fonts: "Source Serif Pro;STKaiti",
                           mn2pdf: { font_manifest: hash_including(
                             "Source Serif Pro" => anything,
                             "STKaiti" => anything,
                           )}))
  end
end
