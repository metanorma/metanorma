# frozen_string_literal: true

require "bundler/setup"
require "metanorma"
require "rspec/matchers"
require "equivalent-xml"
require "rspec-command"
require "mnconvert"
require "mn2pdf"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around do |example|
    Dir.mktmpdir("rspec-") do |dir|
      ["spec/assets/", "spec/examples/", "spec/fixtures/"].each do |assets|
        tmp_assets = File.join(dir, assets)
        FileUtils.rm_rf tmp_assets
        FileUtils.mkdir_p tmp_assets
        FileUtils.cp_r Dir.glob("#{assets}*"), tmp_assets
      end
      Dir.chdir(dir) { example.run }
    end
  end

  config.include RSpecCommand
end

def xmlpp(xml)
  xsl = <<~XSL
    <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:output method="xml" encoding="UTF-8" indent="yes"/>
      <xsl:strip-space elements="*"/>
      <xsl:template match="/">
        <xsl:copy-of select="."/>
      </xsl:template>
    </xsl:stylesheet>
  XSL
  Nokogiri::XSLT(xsl).transform(Nokogiri::XML(xml, &:noblanks))
    .to_xml(indent: 2, encoding: "UTF-8")
end

ASCIIDOC_BLANK_HDR = <<~"HDR"
  = Document title
  Author
  :docfile: test.adoc
  :nodoc:
  :novalid:
  :no-isobib:

HDR

ASCIIDOC_CONFIGURED_HDR = <<~"HDR"
  = Document title
  Author
  :docfile: test.adoc
  :nodoc:
  :novalid:
  :no-isobib:
  :script: script.html
  :body-font: body-font
  :header-font: header-font
  :monospace-font: monospace-font
  :title-font: title-font
  :i18nyaml: i18n.yaml

HDR

ISOXML_BLANK_HDR = <<~"HDR"
  <?xml version="1.0" encoding="UTF-8"?>
  <iso-standard xmlns="http://riboseinc.com/isoxml">
  <bibdata type="article">
    <title>
    </title>
    <title>
    </title>
    <docidentifier>
      <project-number>ISO </project-number>
    </docidentifier>
    <contributor>
      <role type="author"/>
      <organization>
        <name>International Organization for Standardization</name>
        <abbreviation>ISO</abbreviation>
      </organization>
    </contributor>
    <contributor>
      <role type="publisher"/>
      <organization>
        <name>International Organization for Standardization</name>
        <abbreviation>ISO</abbreviation>
      </organization>
    </contributor>
    <script>Latn</script>
    <status>
      <stage>60</stage>
      <substage>60</substage>
    </status>
    <copyright>
      <from>#{Time.new.year}</from>
      <owner>
        <organization>
          <name>International Organization for Standardization</name>
          <abbreviation>ISO</abbreviation>
        </organization>
      </owner>
    </copyright>
    <editorialgroup>
      <technical-committee/>
      <subcommittee/>
      <workgroup/>
    </editorialgroup>
  </bibdata>
  </iso-standard>
HDR

def strip_guid(xml)
  xml.gsub(%r{ id="_[^"]+"}, ' id="_"')
    .gsub(%r{ target="_[^"]+"}, ' target="_"')
end

def mock_pdf
  allow(::Mn2pdf).to receive(:convert) do |url, output, _c, _d|
    FileUtils.cp(url.gsub(/"/, ""), output.gsub(/"/, ""))
  end
end

def mock_sts
  allow(::MnConvert).to receive(:convert) do |url, output, _c|
    FileUtils.cp(url.gsub(/"/, ""), output[:output_file].gsub(/"/, ""))
  end
end

def supress_exit
  yield
rescue SystemExit
end
