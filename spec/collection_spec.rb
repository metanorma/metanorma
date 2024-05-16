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
    it "YAML collection" do
      mock_pdf
      xml_file = "#{INPATH}/collection1.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(xml)).to be_equivalent_to xml_content
    end

    it "YAML collection with docs inline" do
      mock_pdf
      xml_file = "#{INPATH}/collection_docinline.xml"
      mc = Metanorma::Collection
        .parse("#{INPATH}/collection_docinline.yml")
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      expect(xmlpp(cleanup_id(xml)))
        .to be_equivalent_to xmlpp(read_and_cleanup(xml_file))

      newyaml = "#{INPATH}/collection_docinline1.yml"
      File.open newyaml, "w" do |f|
        f.write(File.read("#{INPATH}/collection_docinline.yml")
          .sub(/- documents-inline/, ""))
      end
      mc = Metanorma::Collection.parse(newyaml)
      xml = mc.to_xml
      FileUtils.rm_rf newyaml
      expect(xmlpp(cleanup_id(xml)))
        .to be_equivalent_to xmlpp(read_and_cleanup(xml_file))
    end

    it "YAML collection with interleaved documents and manifests" do
      mock_pdf
      xml_file = "#{INPATH}/collection1nested.xml"
      mc = Metanorma::Collection.parse "#{INPATH}/collection1nested.yml"
      xml = mc.to_xml
      File.write xml_file, xml, encoding: "UTF-8" unless File.exist? xml_file
      expect(mc).to be_instance_of Metanorma::Collection
      xml_content = read_and_cleanup(xml_file)
      expect(cleanup_id(xml)).to be_equivalent_to xml_content
    end

    context "YAML collection with new format" do
      let(:yaml_file) { "#{INPATH}/collection_new.yml" }
      let(:collection_model) { YAML.load_file yaml_file }
      let(:ccm) do
        Metanorma::Collection.send(
          :construct_collection_manifest,
          collection_model,
        )
      end

      describe "when loading new collection yaml file" do
        it "should conform to new format" do
          expect(collection_model).to include("manifest")
          expect(collection_model["manifest"])
            .to include("level" => "collection")
          expect(collection_model["manifest"]).to include("docref")
          expect(collection_model["manifest"]["docref"])
            .to be_an_instance_of(Array)
          collection_model["manifest"]["docref"].each do |i|
            expect(i).to include("file")
          end
        end
      end

      describe "when constructing collection manifest" do
        it "should inherit sectionsplit and have correct format" do
          expect(collection_model).to include("manifest")
          expect(collection_model["manifest"]).to include("sectionsplit")

          # get sectionsplit from source collection model
          sectionsplit = collection_model["manifest"]["sectionsplit"]

          expect(ccm).to include("manifest")
          expect(ccm["manifest"]).to include("manifest")
          expect(ccm["manifest"]).not_to include("docref")
          expect(ccm["manifest"]).not_to include("sectionsplit")
          expect(ccm["manifest"]["manifest"]).to be_an_instance_of(Array)
          ccm["manifest"]["manifest"].each do |i|
            expect(i).to include("level")
            expect(i).to include("title")
            expect(i).to include("docref")
            expect(i["level"]).to eq("document").or eq("attachments")
            i["docref"].each do |dr|
              expect(dr).to include("fileref")
              expect(dr).to include("identifier")
              ext = File.extname(dr["fileref"])
              expect(%w(.adoc .svg .png).include?(ext)).to be true
              if File.extname(dr["fileref"]) == ".adoc"
                # check sectionsplit inheritance
                expect(dr).to include("sectionsplit")
                expect(dr["sectionsplit"]).to eq(sectionsplit)
              else
                expect(dr).to include("attachment")
                expect(dr).not_to include("sectionsplit")
                expect(dr["attachment"]).to eq(true)
              end
            end
          end
        end

        it "should allow user to set identifier" do
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

          expect(ccm).to include("manifest")
          expect(ccm["manifest"]).to include("manifest")
          expect(ccm["manifest"]["manifest"]).to be_an_instance_of(Array)
          ccm["manifest"]["manifest"].each do |i|
            expect(i).to include("docref")
            i["docref"].each do |dr|
              expect(dr).to include("identifier")
              ext = File.extname(dr["fileref"])
              expect(%w(.adoc .svg .png).include?(ext)).to be true
              if File.extname(dr["fileref"]) == ".adoc"
                expect(dr["identifier"]).to match(/^document-[1,2]/)
              elsif File.extname(dr["fileref"]) == ".png"
                expect(dr["identifier"]).to match(/rice_image1\.png/)
              else
                expect(dr["identifier"]).to match(/action_schemaexpg[123]\.svg/)
              end
            end
          end
        end

        it "should allow user to point fileref to new location conditionally" do
          my_fileref_proc = Proc.new do |_ref_folder, fileref|
            if fileref == "img/action_schemaexpg2.svg"
              fileref = fileref.gsub("img/", "image/")
            end
            next fileref
          end
          Metanorma::Collection.set_fileref_resolver(&my_fileref_proc)

          expect(ccm).to include("manifest")
          expect(ccm["manifest"]).to include("manifest")
          expect(ccm["manifest"]["manifest"]).to be_an_instance_of(Array)
          ccm["manifest"]["manifest"].each do |i|
            expect(i).to include("docref")
            i["docref"].each do |dr|
              expect(dr).to include("fileref")
              ext = File.extname(dr["fileref"])
              expect(%w(.adoc .svg .png).include?(ext)).to be true
              if dr["fileref"].match?(/action_schemaexpg2/)
                expect(dr["fileref"])
                  .to match(/^image\/.*/)
              end
            end
          end
        end
      end

      describe "when parsing and rendering model" do
        let(:parse_model) { Metanorma::Collection.parse(yaml_file) }
        let(:collection_opts) do
          {
            format: [:html],
            output_folder: OUTPATH,
            compile: {
              no_install_fonts: true,
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
          Metanorma::Collection.set_pre_parse_model(&my_proc)
          printed = capture_stdout do
            Metanorma::Collection.send(:pre_parse_model, collection_model)
          end
          expect(printed).to include("Test Proc!")
        end

        it "should raise error if adoc files not found" do
          my_dumb_fileref_proc = Proc.new do |_ref_folder, fileref|
            fileref = "dunno/#{fileref}"
            next fileref
          end

          Metanorma::Collection.set_fileref_resolver(&my_dumb_fileref_proc)

          expect { parse_model.render(collection_opts) }.to raise_error(
            Metanorma::AdocFileNotFoundException, /document-1\.adoc not found!/
          )
        end

        it "should compile adoc files and return Metanorma::Collection" do
          Metanorma::Collection.unset_fileref_resolver
          xml_paths = [
            "#{INPATH}/document-1/document-1.xml",
            "#{INPATH}/document-2/document-2.xml",
          ]
          xml_paths.each do |x|
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
            "document-1_index.html" => "ISO 12345-1:2024",
            "document-2_index.html" => "ISO 12345-2:2024",
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
      expect(cleanup_id(mc.to_xml)).to be_equivalent_to xml
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
      expect(xmlpp(cleanup_id(mc.to_xml))).to be_equivalent_to xmlpp(xml)
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
