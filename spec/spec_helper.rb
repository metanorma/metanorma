# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
end

require "bundler/setup"
require "metanorma"
require "rspec/matchers"
require "equivalent-xml"
require "rspec-command"
require "mnconvert"
require "mn2pdf"
require "xml-c14n"
require_relative "support/uuid_mock"

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

ASCIIDOC_BLANK_HDR = <<~HDR
  = Document title
  Author
  :docfile: test.adoc
  :nodoc:
  :novalid:
  :no-isobib:

HDR

ISOXML_BLANK_HDR = <<~HDR
  <?xml version="1.0" encoding="UTF-8"?>
  <metanorma xmlns="http://riboseinc.com/isoxml">
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
  </metanorma>
HDR

GUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(_[^'\" ]+)?"

def strip_guid(xml)
  xml.gsub(%r{ id="_[^"]+"}, ' id="_"')
    .gsub(%r{ semx-id="[^"]*"}, "")
    .gsub(%r{ target="_[^"]+"}, ' target="_"')
end

def cleanup_guid(content)
  content
    .gsub(%r{cid:#{GUID}}o, "cid:_")
    .gsub(%r{ semx-id="[^"]*"}o, "")
    .gsub(%r{ id="_#{GUID}"}o, ' id="_"')
    .gsub(%r{ id="_#{GUID}_[^"]+"}o, ' id="_"')
    .gsub(%r{ target="_#{GUID}"}o, ' target="_"')
    .gsub(%r{ source="_#{GUID}"}o, ' source="_"')
    .gsub(%r{ original-id="_#{GUID}"}o, ' original-id="_"')
    .gsub(%r{ name="_#{GUID}"}o, ' name="_"')
    .gsub(%r{ name="_#{GUID}_[^"]+"}o, ' name="_"')
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

def mock_pdf
  allow(Mn2pdf).to receive(:convert) do |url, output, _c, _d|
    FileUtils.cp(url.gsub('"', ""), output.gsub('"', ""))
  end
end

def mock_pdf_portfolio
  @pdf_portfolio_option = nil
  mock_pdf_portfolio_options_to_cmd
  mock_pdf_portfolio_convert
end

def mock_pdf_portfolio_options_to_cmd
  # Intercept options_to_cmd to capture the options
  allow(Mn2pdf).to receive(:options_to_cmd) do |options|
    # Capture what options are passed
    if options.respond_to?(:attr)
      # If it's a PdfOptionsNode with attr method
      @pdf_portfolio_option = options.attr("pdf-portfolio")
    elsif options.is_a?(Hash)
      # If it's a Hash with "--pdf-portfolio" key
      @pdf_portfolio_option = options["--pdf-portfolio"] ||
        options[:"--pdf-portfolio"]
    end
    # Return empty string as options_to_cmd normally would
    ""
  end
end

def mock_pdf_portfolio_convert
  # Mock convert to call options_to_cmd then copy file (not run Java)
  allow(Mn2pdf).to receive(:convert) do |url, output, _c, options_node|
    output.end_with?("collection.portfolio.pdf") or
      @pdf_portfolio_option = nil
    # Call options_to_cmd like the real method would
    Mn2pdf.options_to_cmd(options_node) if options_node
    # Then just copy the file instead of running Java
    FileUtils.cp(url.gsub('"', ""), output.gsub('"', ""))
  end
end

def pdf_portfolio_used?
  @pdf_portfolio_option == "true"
end

def mock_sts
  allow(MnConvert).to receive(:convert) do |url, output, _c|
    FileUtils.cp(url.gsub('"', ""), output[:output_file].gsub('"', ""))
  end
end

def supress_exit
  yield
rescue SystemExit
end
