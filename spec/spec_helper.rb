# frozen_string_literal: true

require "bundler/setup"
require "metanorma"
require "rspec/matchers"
require "equivalent-xml"
require "rspec-command"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.include RSpecCommand
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
