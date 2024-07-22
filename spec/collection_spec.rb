# frozen_string_literal: true

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
OUTPATH = "spec/fixtures/ouput"

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
        - coverpage: spec/fixtures/collection/collection_cover.html
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
          ext:
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
              index: true
              file: rice-en.final.xml
              entry: []
              bibdata:
            - identifier: ISO 17302:2016
              url: example/url
              index: true
              file: dummy.xml
              entry: []
              bibdata:
            - identifier: ISO 1701:1974
              index: true
              file: rice1-en.final.xml
              entry: []
              bibdata:
            bibdata:
          - type: subcollection
            title: Amendments
            index: true
            entry:
            - identifier: ISO 17301-1:2016/Amd.1:2017
              index: true
              file: rice-amd.final.xml
              entry: []
              bibdata:
            bibdata:
          - type: attachments
            title: Attachments
            index: true
            entry:
            - identifier: action_schemaexpg1.svg
              attachment: true
              index: true
              file: pics/action_schemaexpg1.svg
              entry: []
              bibdata:
            - identifier: rice_image1.png
              attachment: true
              index: true
              file: "../../assets/rice_image1.png"
              entry: []
              bibdata:
            bibdata:
          bibdata:
        format: []
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
      expect(cleanup_id(Xml::C14n.format(xml))).to be_equivalent_to Xml::C14n.format(xml_content)
    end

    it "YAML collection with no document identifiers" do
      mock_pdf
      xml_file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1noid.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(Xml::C14n.format(xml))).to be_equivalent_to Xml::C14n.format(xml_content)
    end

    it "YAML collection with docs inline" do
      mock_pdf
      xml_file = "#{INPATH}/collection_docinline.xml"
      mc = Metanorma::Collection
        .parse("#{INPATH}/collection_docinline.yml")
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      expect(Xml::C14n.format(cleanup_id(xml)))
        .to be_equivalent_to Xml::C14n.format(read_and_cleanup(xml_file))

      newyaml = "#{INPATH}/collection_docinline1.yml"
      File.open newyaml, "w" do |f|
        f.write(File.read("#{INPATH}/collection_docinline.yml")
          .sub(/- documents-inline/, ""))
      end
      mc = Metanorma::Collection.parse(newyaml)
      xml = mc.to_xml
      FileUtils.rm_rf newyaml
      expect(Xml::C14n.format(cleanup_id(xml)))
        .to be_equivalent_to Xml::C14n.format(read_and_cleanup(xml_file))
    end

    it "YAML collection with interleaved documents and manifests" do
      mock_pdf
      xml_file = "#{INPATH}/collection1nested.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1nested.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(Xml::C14n.format(cleanup_id(xml))).to be_equivalent_to Xml::C14n.format(xml_content)
    end

    context "YAML collection with new format" do
      let(:yaml_file) { "#{INPATH}/collection_new.yml" }
      let(:ccm) do
        Metanorma::Collection.parse(yaml_file).manifest
          .to_xml(Nokogiri::XML::Builder.new).to_xml
      end

      describe "when constructing collection manifest" do
        it "should inherit sectionsplit and have correct format" do
          expect(Xml::C14n.format(cleanup_id(ccm)))
            .to be_equivalent_to Xml::C14n.format(cleanup_id(<<~OUTPUT))
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
                      <entry id="doc000000000" sectionsplit="true" index="true" fileref="document-1/document-1.xml">
                        <identifier>ISO 12345-1:2024</identifier>
                      </entry>
                    </entry>
                    <entry index="true">
                      <identifier>eb779c1d-f770-47e4-9d5f-83958e59be0f</identifier>
                      <type>attachments</type>
                      <title>Attachments</title>
                      <entry id="doc000000001" attachment="true" index="true" fileref="document-1/img/action_schemaexpg2.svg">
                        <identifier>action_schemaexpg2.svg</identifier>
                      </entry>
                      <entry id="doc000000002" attachment="true" index="true" fileref="../../assets/rice_image1.png">
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
                      <entry id="doc000000003" sectionsplit="true" index="true" fileref="document-2/document-2.xml">
                        <identifier>ISO 12345-2:2024</identifier>
                      </entry>
                    </entry>
                    <entry index="true">
                      <identifier>380c7f48-59e5-44c8-b5db-5ac5d79c12f3</identifier>
                      <type>attachments</type>
                      <title>Attachments</title>
                      <entry id="doc000000004" attachment="true" index="true" fileref="document-2/img/action_schemaexpg3.svg">
                        <identifier>action_schemaexpg3.svg</identifier>
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
          id = xml.at("//entry[@id = 'doc000000001']/@fileref")
          expect(id.text).to eq "document-1/image/action_schemaexpg2.svg"
        end
      end

      describe "when parsing and rendering model" do
        let(:parse_model) { Metanorma::Collection.parse(yaml_file) }
        let(:collection_opts) do
          {
            format: [:html],
            output_folder: OUTPATH,
            compile: {
              install_fonts: false,
            },
            coverpage: "#{INPATH}/cover1.html",
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
        end
      end
    end

    it "XML collection" do
      mock_pdf
      file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse file
      expect(mc).to be_instance_of Metanorma::Collection
      xml = cleanup_id File.read(file, encoding: "UTF-8")
      expect(cleanup_id(Xml::C14n.format(mc.to_xml))).to be_equivalent_to Xml::C14n.format(xml)
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
      expect(Xml::C14n.format(cleanup_id(mc.to_xml))).to be_equivalent_to Xml::C14n.format(xml)
    end
  end

  private

  GUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  def cleanup_guid(content)
    content
      .gsub(%r{cid:#{GUID}}o, "cid:_")
      .gsub(%r{ id="_#{GUID}"}o, ' id="_"')
      .gsub(%r{ name="_#{GUID}"}o, ' name="_"')
      .gsub(%r{_Toc[0-9]{9}}o, "_Toc")
  end

  def read_and_cleanup(file)
    content = File.read(file, encoding: "UTF-8").gsub(
      /(?<=<fetched>)\d{4}-\d{2}-\d{2}/, Date.today.to_s
    )
    cleanup_id content
  end

  def cleanup_id(content)
    content.gsub(/(?<=<p id=")[^"]+/, "")
      .gsub(%r{data:image/svg\+xml[^<"']+}, "data:image/svg+xml")
      .gsub(%r{data:image/png[^<"']+}, "data:image/png")
      .gsub(/ schema-version="[^"]+"/, "")
      .gsub(%r{<identifier>#{GUID}</identifier>}o, "<identifier>_</identifier>")
  end
end
