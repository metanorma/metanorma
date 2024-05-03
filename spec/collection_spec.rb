# frozen_string_literal: true
require 'stringio'

def capture_stdout(&blk)
  old = $stdout
  $stdout = fake = StringIO.new
  blk.call
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
      let(:yaml_file) { "collection_new.yml" }
      let(:collection_model) { YAML.load_file "#{INPATH}/#{yaml_file}" }
      let(:ccm) {
        Metanorma::Collection.send(
          :construct_collection_manifest,
          collection_model
        )
      }

      describe "when loading new collection yaml file" do
        it "should conform to new format" do
          expect(collection_model).to include('manifest')
          expect(
            collection_model['manifest']
          ).to include('level' => 'collection')
          expect(collection_model['manifest']).to include('docref')
          expect(
            collection_model['manifest']['docref']
          ).to be_an_instance_of(Array)
          collection_model['manifest']['docref'].each do |i|
            expect(i).to include('file')
          end
        end
      end

      describe "when constructing collection manifest" do
        it "should inherit sectionsplit and have correct format" do
          expect(collection_model).to include('manifest')
          expect(collection_model['manifest']).to include('sectionsplit')

          # get sectionsplit from source collection model
          sectionsplit = collection_model['manifest']['sectionsplit']

          expect(ccm).to include('manifest')
          expect(ccm['manifest']).to include('manifest')
          expect(ccm['manifest']).not_to include('docref')
          expect(ccm['manifest']).not_to include('sectionsplit')
          expect(ccm['manifest']['manifest']).to be_an_instance_of(Array)
          ccm['manifest']['manifest'].each do |i|
            expect(i).to include('level')
            expect(i).to include('title')
            expect(i).to include('docref')
            expect(i['level']).to eq('document').or eq('attachments')
            i['docref'].each do |dr|
              expect(dr).to include('fileref')
              expect(dr).to include('identifier')
              expect(File.extname(dr['fileref'])).to eq('.adoc').or eq('.svg')
              if File.extname(dr['fileref']) == '.adoc'
                # check sectionsplit inheritance
                expect(dr).to include('sectionsplit')
                expect(dr['sectionsplit']).to eq(sectionsplit)
              else
                expect(dr).to include('attachment')
                expect(dr).not_to include('sectionsplit')
                expect(dr['attachment']).to eq(true)
              end
            end
          end
        end

        it "should allow user to set indentifier" do
          my_identifier_proc = Proc.new do |identifier|
            identifier = case identifier
                         when /^spec\/fixtures\/collection\//
                           identifier.gsub('spec/fixtures/collection/', '')
                         else
                           identifier
                         end
            next identifier
          end
          Metanorma::Collection.set_indentifier_resolver(&my_identifier_proc)

          expect(ccm).to include('manifest')
          expect(ccm['manifest']).to include('manifest')
          expect(ccm['manifest']['manifest']).to be_an_instance_of(Array)
          ccm['manifest']['manifest'].each do |i|
            expect(i).to include('docref')
            i['docref'].each do |dr|
              expect(dr).to include('identifier')
              expect(File.extname(dr['fileref'])).to eq('.adoc').or eq('.svg')
              if File.extname(dr['fileref']) == '.adoc'
                # set new identifier value if not present
                expect(dr['identifier']).to match(/^document-[1,2]/)
              else
                # follow original identifier value if present
                expect(dr['identifier']).to eq('action_schemaexpg1.svg')
              end
            end
          end
        end

        it "should allow user to point fileref to new location conditionally" do
          my_fileref_proc = Proc.new do |ref_folder, fileref|
            if File.extname(fileref) == '.svg'
              fileref = fileref.gsub(
                'spec/fixtures/collection',
                'new/location'
              )
            end
            next fileref
          end
          Metanorma::Collection.set_fileref_resolver(&my_fileref_proc)

          expect(ccm).to include('manifest')
          expect(ccm['manifest']).to include('manifest')
          expect(ccm['manifest']['manifest']).to be_an_instance_of(Array)
          ccm['manifest']['manifest'].each do |i|
            expect(i).to include('docref')
            i['docref'].each do |dr|
              expect(dr).to include('fileref')
              expect(File.extname(dr['fileref'])).to eq('.adoc').or eq('.svg')
              if File.extname(dr['fileref']) == '.svg'
                expect(
                  dr['fileref']
                ).to match(/^new\/location\/.*/)
              else
                expect(
                  dr['fileref']
                ).to match(/^document-[1,2].*/)
              end
            end
          end
        end
      end

      describe "when parsing and rendering model" do
        let(:parse_model) {
          Metanorma::Collection.parse_model(yaml_file, collection_model)
        }
        let(:collection_opts) {
          {
            format: [:html],
            output_folder: OUTPATH,
            compile: {
              no_install_fonts: true
            },
            coverpage: "#{INPATH}/cover1.html"
          }
        }
        let(:compile_adoc) {
          Metanorma::Collection.send(
            :compile_adoc_documents,
            collection_model
          )
        }

        before do
          my_identifier_proc = Proc.new do |identifier|
            identifier = case identifier
                         when /^spec\/fixtures\/collection\//
                           identifier.gsub('spec/fixtures/collection/', '')
                         else
                           identifier
                         end
            next identifier
          end

          my_fileref_proc = Proc.new do |ref_folder, fileref|
            if File.extname(fileref) == '.adoc'
              fileref = fileref.gsub(
                /^document/,
                "#{ref_folder}/document"
              )
            end
            next fileref
          end

          Metanorma::Collection.set_indentifier_resolver(&my_identifier_proc)
          Metanorma::Collection.set_fileref_resolver(&my_fileref_proc)
        end

        it "should allow user to define a proc to run" do
          my_proc = Proc.new do |collection_model|
            puts "Test Proc!"
          end
          Metanorma::Collection.set_pre_parse_model(&my_proc)
          printed = capture_stdout { parse_model }
          expect(printed).to include("Test Proc!")
        end

        it "should raise error if adoc files not found" do
          my_fileref_proc = nil
          Metanorma::Collection.set_fileref_resolver(&my_fileref_proc)
          expect{ parse_model }.to raise_error(
            Metanorma::AdocFileNotFoundException, 'document-1.adoc not found!'
          )
        end

        it "should compile adoc files and return Metanorma::Collection" do
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
          parse_model.render(collection_opts)

          expected_output = {
            'index.html'            => 'Cover bibdata - Test Title 12345',
            'document-1_index.html' => 'ISO 12345-1:2024',
            'document-2_index.html' => 'ISO 12345-2:2024',
          }
          generated_files = Dir["#{OUTPATH}/*"]

          expected_output.each do |k, v|
            expect(generated_files).to include("#{OUTPATH}/#{k}")
            expect(
              File.read("#{OUTPATH}/#{k}", encoding: "utf-8")
            ).to include(v)
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

  context "render html & build doc, pdf, xml files from" do
    it "YAML collection" do # rubocop:disable metrics/blocklength
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.rm_f "#{OUTPATH}/collection1.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml],
        output_folder: of,
        # coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      concat_text = read_and_cleanup "#{INPATH}/collection_full.xml"
      concat_file = read_and_cleanup "#{OUTPATH}/collection.xml"
      expect(xmlpp(concat_file.gsub("><", ">\n<"))
        .sub(%r{xlink:href=['"]data:image/gif;base64,[^']*'},
             "xlink:href='data:image/gif;base64,_'"))
        .to be_equivalent_to xmlpp(concat_text.gsub("><", ">\n<"))
          .sub(%r{xlink:href=['"]data:image/gif;base64[^']*'},
               "xlink:href='data:image/gif;base64,_'")
      conact_file_doc_xml = Nokogiri::XML(concat_file)
      concat_text_doc_xml = File.open("#{INPATH}/rice-en.final.xml") do |f|
        Nokogiri::XML(f)
      end

      %w[
        Dummy_ISO_17301-1_2016
        StarTrek_ISO_17301-1_2016
        RiceAmd_ISO_17301-1_2016
        _scope_ISO_1701_1974
        _introduction_ISO_17301-1_2016_Amd.1_2017
      ].each do |id|
        expect(conact_file_doc_xml.xpath(IsoDoc::Convert.new({})
          .ns("//*[@id='#{id}']")).length).to_not be_zero
      end
      expect(concat_text_doc_xml.xpath("//xmlns:xref/@target")[-1].text)
        .to be_equivalent_to "_scope"
      expect(conact_file_doc_xml.xpath("//i:xref/@target", "i" => "https://www.metanorma.org/ns/iso")[-1].text)
        .to be_equivalent_to "_scope_ISO_17301-1_2016"
      expect(concat_text_doc_xml.at("//xmlns:strong/@style").text)
        .to be_equivalent_to "background: url(#svg1); foreground: url(_001); middleground: url(#fig1);"
      expect(conact_file_doc_xml.at("//i:strong/@style", "i" => "https://www.metanorma.org/ns/iso").text)
        .to be_equivalent_to "background: url(#svg1_ISO_17301-1_2016); foreground: url(_001); middleground: url(#fig1_ISO_17301-1_2016);"

      expect(File.exist?("#{INPATH}/collection1.err.html")).to be true
      expect(File.read("#{INPATH}/collection1.err.html", encoding: "utf-8"))
        .to include "Missing:​express-schema:​E0"
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1"
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "ISO 17301-1:2016/Amd.1:2017"
      expect(File.exist?("#{OUTPATH}/pics/action_schemaexpg1.svg")).to be true
      expect(File.exist?("#{OUTPATH}/assets/rice_image1.png")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.read("#{OUTPATH}/dummy.xml"))
        .not_to be_equivalent_to File.read("#{OUTPATH}/dummy.presentation.xml")
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      rice = File.read("#{OUTPATH}/rice-en.final.html")
      expect(rice).to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      expect(rice).to include %(It is not applicable to cooked rice products, which are not discussed in <a href="#anotherclause_ISO_17301-1_2016"><span class="citesec">Clause 2</span></a> or <a href="#thirdclause_ISO_17301-1_2016"><span class="citesec">Clause 3</span></a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # but that document is not supplied
      expect(rice).to include %{This document uses schemas E0/A0, <a href="example/url.html#A1">E1/A1</a> and <a href="example/url.html#E2">E2</a>.}
      expect(rice).to include %(This document is also unrelated to <a href="example/url.html#what">)
      FileUtils.rm_rf of
    end

    it "extracts metadata from collection for Liquid" do
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      cr = Metanorma::CollectionRenderer
        .render(col,
                format: %i[presentation html xml],
                output_folder: of,
                coverpage: "#{INPATH}/collection_cover.html",
                compile: {
                  no_install_fonts: true,
                })
      expect(cr.isodoc.meta.get[:docrefs])
        .to be_equivalent_to [
          { "identifier" => "ISO 17301-1:2016", "file" => "rice-en.final.html",
            "title" => "Cereals and pulses&#x2009;&#x2014;&#x2009;" \
                       "Specifications and test methods&#x2009;&#x2014;" \
                       "&#x2009;Rice (Final)", "level" => nil },
          { "identifier" => "ISO 17302", "file" => "dummy.html",
            "title" => "Dummy document", "level" => nil },
          { "identifier" => "ISO 1701:1974", "file" => "rice1-en.final.html",
            "title" => "Test conditions for milling machines with table of " \
                       "variable height, with horizontal or vertical spindle",
            "level" => nil },
          { "identifier" => "ISO 17301-1:2016/Amd.1:2017",
            "file" => "rice-amd.final.html",
            "title" => "Specification and test methods&#x2009;&#x2014;&#x2009;" \
                       "Rice&#x2009;&#x2014;&#x2009;Mass fraction of " \
                       "extraneous matter, milled rice (nonglutinous), sample " \
                       "dividers and recommendations relating to storage and " \
                       "transport conditions", "level" => nil },
          { "identifier" => "action_schemaexpg1.svg",
            "file" => "pics/action_schemaexpg1.svg", "title" => nil,
            "level" => nil },
          { "identifier" => "rice_image1.png",
            "file" => "assets/rice_image1.png",
            "title" => nil, "level" => nil },
        ]
      expect(cr.isodoc.meta.get[:navigation])
        .to be_equivalent_to <<~OUTPUT
          <ul>
          <li>ISO Collection</li>
          <ul>
          <li>Standards</li>
          <ul>
          <li><a href="rice-en.final.html">ISO&nbsp;17301-1:2016</a></li>
          <li><a href="dummy.html">ISO&nbsp;17302</a></li>
          <li><a href="rice1-en.final.html">ISO&nbsp;1701:1974</a></li>
          </ul>
          </ul>
          <ul>
          <li>Amendments</li>
          <ul><li><a href="rice-amd.final.html">ISO 17301-1:2016/Amd.1:2017</a></li></ul>
          </ul>
          <ul>
          <li>Attachments</li>
          <ul>
          <li><a href="pics/action_schemaexpg1.svg">action_schemaexpg1.svg</a></li>
          <li><a href="assets/rice_image1.png">rice_image1.png</a></li>
          </ul>
          </ul>
          </ul>
        OUTPUT
      expect(strip_guid(cr.isodoc.meta.get[:"prefatory-content"]))
        .to be_equivalent_to <<~OUTPUT
          <div>
          <div id="_">
          <h1>Clause</h1>

          <p id="_">Welcome to our collection</p>
          </div>
          </div>
      OUTPUT
      expect(strip_guid(cr.isodoc.meta.get[:"final-content"]))
        .to be_equivalent_to <<~OUTPUT
           <div>
          <div id="_">
          <h1>Exordium</h1>

          <p id="_">Hic explicit</p>
          </div>
          </div>
      OUTPUT
      expect(cr.isodoc.meta.get[:nav_object])
        .to be_equivalent_to (
          { title: "ISO Collection",
            children: [
              { title: "Standards",
                docrefs: <<~DOCREF,
                  <ul><li><a href="rice-en.final.html">ISO&nbsp;17301-1:2016</a></li><li><a href="dummy.html">ISO&nbsp;17302</a></li><li><a href="rice1-en.final.html">ISO&nbsp;1701:1974</a></li></ul>
                DOCREF
              },
              { title: "Amendments",
                docrefs: <<~DOCREF,
                  "<ul><li><a href="rice-amd.final.html">ISO 17301-1:2016/Amd.1:2017</a></li></ul>"
                DOCREF
              },
              { title: "Attachments",
                docrefs: <<~DOCREF,
                  "<ul><li><a href="pics/action_schemaexpg1.svg">action_schemaexpg1.svg</a></li><li><a href="assets/rice_image1.png">rice_image1.png</a></li></ul>"
                DOCREF
              },
            ] }
        )
    end

    it "uses presentation XML directive, markup in identifiers" do # rubocop:disable metrics/blocklength
      mock_pdf
      FileUtils.rm_f "#{OUTPATH}/collection.err.html"
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection2.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[html presentation xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.read("#{OUTPATH}/dummy.xml"))
        .to be_equivalent_to File.read("#{OUTPATH}/dummy.presentation.xml")
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "1701<sup>x</sup>"
      FileUtils.rm_rf of
    end

    it "YAML collection with documents inline" do # rubocop:disable metrics/blocklength
      mock_pdf
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg", "action_schemaexpg1.svg"
      file = "#{INPATH}/collection1.yml"
      # xml = file.read file, encoding: "utf-8"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html pdf xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/index.html")).to be true
      expect(File.read("#{OUTPATH}/index.html", encoding: "utf-8"))
        .to include "<h1>ISO Collection 1"
      expect(File.exist?("#{OUTPATH}/dummy.html")).to be true
      # expect(File.exist?("#{OUTPATH}/dummy.doc")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
      expect(File.exist?("#{OUTPATH}/dummy.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-amd.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-amd.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml"))
        .to be true
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml.0.html"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml.1.html"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice-en.final.presentation.xml.2.html"))
        .to be false
      expect(File.exist?("#{OUTPATH}/rice1-en.final.html")).to be true
      # expect(File.exist?("#{OUTPATH}/rice1-en.final.doc")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.pdf")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.xml")).to be true
      expect(File.exist?("#{OUTPATH}/rice1-en.final.presentation.xml"))
        .to be true
      FileUtils.rm_rf of
    end

    it "YAML collection with multiple documents sectionsplit (source document for links)" do # rubocop:disable metrics/blocklength
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_sectionsplit.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{INPATH}/ISO 17301-1_2016_index.html")).to be false
      expect(File.exist?("#{OUTPATH}/ISO 17301-1_2016_index.html")).to be true
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
      rice = File.read("#{OUTPATH}/rice-en.final.xml.1.html")
      expect(rice).to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      expect(rice).to include %(It is not applicable to cooked rice products, which are not discussed in <a href="rice-en.final.xml.2.html#anotherclause_ISO_17301-1_2016_ISO_17301-1_2016_2_This_is_another_clause"><span class="citesec">Clause 2</span></a> or <a href="rice-en.final.xml.3.html#thirdclause_ISO_17301-1_2016_ISO_17301-1_2016_3_This_is_another_clause"><span class="citesec">Clause 3</span></a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # but that document is not supplied
      expect(rice).to match %r{This document uses schemas E0/A0, <a href="dummy.html#express-schema_E1_ISO_17302">E1/A1</a> and <a href="dummy.html#express-schema_E2_ISO_17302">express-schema/E2</a>.}
      expect(rice).to include %(This document is also unrelated to <a href="dummy.html#what">)
      xml = Nokogiri::XML(File.read("#{OUTPATH}/rice-en.final.xml.1.presentation.xml"))
      p = xml.xpath("//xmlns:sections//xmlns:p")[4]
      p.delete("id")
      expect(p.to_xml).to be_equivalent_to <<~OUTPUT
        <p>This document is updated in <link target="rice-amd.final.html"><span class="stdpublisher">ISO</span> <span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</link>.</p>
      OUTPUT
      FileUtils.rm_rf of
    end

    it "YAML collection with multiple documents sectionsplit (target document for links)" do # rubocop:disable metrics/blocklength
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_target_sectionsplit.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("rice-en.final.presentation.xml.0.xml")).to be false
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{INPATH}/ISO 17302_index.html")).to be false
      expect(File.exist?("#{OUTPATH}/ISO 17302_index.html")).to be true
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
        .to include %(This document is updated in <a href="rice-amd.final.html"><span class="stdpublisher">ISO </span><span class="stddocNumber">17301</span>-<span class="stddocPartNumber">1</span>:<span class="stdyear">2016</span>/Amd.1:2017</a>.</p>)
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %(It is not applicable to cooked rice products, which are not discussed in <a href="#anotherclause_ISO_17301-1_2016"><span class="citesec">Clause 2</span></a> or <a href="#thirdclause_ISO_17301-1_2016"><span class="citesec">Clause 3</span></a>.</p>)
      # demonstrate that erefs are removed if they point to another document in the repository,
      # and point to the right sectionsplit file
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %(This document is also unrelated to <a href="dummy.xml.3.html#what">)
      expect(File.read("#{OUTPATH}/rice-en.final.html"))
        .to include %{This document is also unrelated to <a href="dummy.xml.3.html#what">current-metanorma-collection/ISO 17302 3 What?</a>.</p><p id="_001_ISO_17301-1_2016">This document uses schemas E0/A0, <a href="dummy.xml.2.html#A1_ISO_17302_ISO_17302_2">E1/A1</a> and <a href="dummy.xml.4.html#E2_ISO_17302_ISO_17302_4">E2</a>.</p>}
      FileUtils.rm_rf of
    end

    xit "YAML collection with single document sectionsplit" do # rubocop:disable metrics/blocklength
      FileUtils.cp "#{INPATH}/action_schemaexpg1.svg",
                   "action_schemaexpg1.svg"
      file = "#{INPATH}/collection_sectionsplit_solo.yml"
      of = OUTPATH.to_s
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation html xml],
        output_folder: of,
        coverpage: "#{INPATH}/collection_cover.html",
        compile: {
          no_install_fonts: true,
        },
      )
      expect(File.exist?("#{OUTPATH}/collection.xml")).to be true
      expect(File.exist?("#{OUTPATH}/collection.presentation.xml")).to be true
      expect(File.exist?("#{OUTPATH}/ISO 17301-1_2016_index.html")).to be false
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
        .to include %(This document uses schemas E0/A0, E1/A1 and E2/A2.)
      expect(File.read("#{OUTPATH}/rice-en.final.xml.1.html"))
        .to include %(This document is also unrelated to <a href="dummy.html#what">)
      FileUtils.rm_rf of
    end
  end

  it "disambiguates destination filenames" do
    file = "#{INPATH}/collection.dup.yml"
    of = OUTPATH
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml],
      output_folder: of,
      coverpage: "#{INPATH}/collection_cover.html",
      compile: {
        no_install_fonts: true,
      },
    )
    expect(File.exist?("#{OUTPATH}/dummy.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.1.xml")).to be true
    expect(File.exist?("#{OUTPATH}/dummy.2.xml")).to be true
    FileUtils.rm_rf of
  end

  it "skips indexing of files in coverpage on request" do
    file = "#{INPATH}/collection.dup.yml"
    of = OUTPATH
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "#{INPATH}/collection_cover.html",
      compile: {
        no_install_fonts: true,
      },
    )
    index = File.read("#{OUTPATH}/index.html")
    expect(index).to include "ISO&nbsp;44001"
    expect(index).not_to include "ISO&nbsp;44002"
    expect(index).to include "ISO&nbsp;44003"
    FileUtils.rm_rf of
  end

  it "injects repository identifiers" do
    file = "#{INPATH}/collection1.norepo.yml"
    of = OUTPATH
    col = Metanorma::Collection.parse file
    col.render(
      format: %i[presentation xml html],
      output_folder: of,
      coverpage: "#{INPATH}/collection_cover.html",
      compile: {
        no_install_fonts: true,
      },
    )
    index = File.read("#{OUTPATH}/rice-en.final.norepo.xml")
    expect(index).to include "Mass fraction of extraneous matter, milled rice " \
                             "(nonglutinous), sample dividers and " \
                             "recommendations relating to storage and " \
                             "transport conditions"
    # has successfully mapped identifier of ISO 17301-1:2016/Amd.1:2017 in
    # rice-en.final.norepo.xml to the file in the collection, and imported its bibdata
    FileUtils.rm_rf of
  end

  context "Word collection" do
    it "builds Word collection, no coverpages" do
      file = "#{INPATH}/wordcollection.yml"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation doc],
        output_folder: of,
        compile: {
          no_install_fonts: true,
        },
      )
      output = File.read("#{OUTPATH}/collection.doc")
      expected = File.read("#{INPATH}/collection.doc")
      # the two images made it into the document
      expect(output).to include "iVBORw0KGgoAAAANSUhEUgAAAaQAAAJnCAYAAADY2CeyAAAAAXNSR0IArs4c6QAAAARnQU1BAACx"
      expect(output).to include "CCQAQAoEEgAgBQIJAJACgQQASIFAAgCkQCABAFIgkAAAKRBIAIAUCCQAQAoEEgAgBQIJAJACgQQA"
      expect(output).to include "mIAkDAAAYAKSMAAAgAlIwgAAACYgCQMAAJiAJAwAAGACkjAAAIAJSMIAAAAmIAkDAACYgCQMAABg"
      expect(output).to include "Content-Type: image/png"
      output.sub!(%r{</html>.*$}m, "</html>").sub!(%r{^.*<html }m, "<html ")
        .sub!(%r{<style>.+</style>}m, "<style/>")
      expect(cleanup_guid(cleanup_id(output)))
        .to be_equivalent_to cleanup_guid(expected)
      FileUtils.rm_rf of
    end

    it "builds Word collection, coverpages" do
      file = "#{INPATH}/wordcollection_cover.yml"
      of = OUTPATH
      col = Metanorma::Collection.parse file
      col.render(
        format: %i[presentation doc],
        output_folder: of,
        compile: {
          no_install_fonts: true,
        },
      )
      output = File.read("#{OUTPATH}/collection.doc")
      expected = File.read("#{INPATH}/collection1.doc")
      output.sub!(%r{</html>.*$}m, "</html>").sub!(%r{^.*<html }m, "<html ")
        .sub!(%r{<style>.+</style>}m, "<style/>")
      expect(cleanup_guid(cleanup_id(output)))
        .to be_equivalent_to cleanup_guid(expected)
      FileUtils.rm_rf of
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
