require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Output::Pdf do
  ASSETS_DIR = 'spec/assets/test'
  INPUT = "#{ASSETS_DIR}/a.html"
  INPUT_CONTENT = "<html><head/><body><h1>Hello</h1></body></html>"
  OUTPUT = "#{ASSETS_DIR}/a.pdf"
  DROP = [INPUT, OUTPUT]

  it "generates a PDF" do
    FileUtils.rm_f DROP
    FileUtils.mkdir_p ASSETS_DIR
    File.write(INPUT, INPUT_CONTENT)

    generator = Metanorma::Output::Pdf.new

    generator.convert(INPUT, OUTPUT)
    expect(File.exist?(OUTPUT)).to be true
  end

  it "handle absolute path" do
    FileUtils.rm_f DROP
    FileUtils.mkdir_p ASSETS_DIR
    File.write(INPUT, INPUT_CONTENT)

    generator = Metanorma::Output::Pdf.new

    generator.convert(File.join(Dir.pwd, INPUT), File.join(Dir.pwd, OUTPUT))
    expect(File.exist?(File.join(Dir.pwd, OUTPUT))).to be true
  end

  it "handle url as input" do
    FileUtils.rm_f DROP
    FileUtils.mkdir_p ASSETS_DIR
    File.write(INPUT, INPUT_CONTENT)

    generator = Metanorma::Output::Pdf.new

    generator.convert("file://#{File.join(Dir.pwd, INPUT)}", OUTPUT)
    expect(File.exist?(OUTPUT)).to be true
  end

  it "Missing input path" do
    generator = Metanorma::Output::Pdf.new
    expect { generator.convert("random.html", "random.pdf") }.to raise_error
  end

  it "Path with spaces" do
    dir = File.join(ASSETS_DIR, "dir with path")
    input = File.join(dir, "a.html")
    output = File.join(dir, "a.pdf")
    FileUtils.rm_f [input, output]
    FileUtils.mkdir_p dir
    File.write(input, INPUT_CONTENT)
    generator = Metanorma::Output::Pdf.new

    generator.convert(input, output)

    expect(File.exist?(output)).to be true
  end
end

RSpec.describe Metanorma::Output::XslfoPdf do
  it "generates a PDF from HTML" do
    FileUtils.rm_f %w(a.pdf)
    generator = Metanorma::Output::XslfoPdf.new
    generator.convert("spec/assets/a.xml", "a.pdf", File.join(File.dirname(__FILE__), "assets", "iso.international-standard.xsl"))
    expect(File.exist?("a.pdf")).to be true
  end
end

