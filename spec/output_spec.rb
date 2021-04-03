require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Output::XslfoPdf do
  ASSETS_DIR = "spec/assets/outputtest".freeze
  INPUT = "#{ASSETS_DIR}/a.xml".freeze
  OUTPUT = "#{ASSETS_DIR}/a.pdf".freeze
  DROP = [OUTPUT].freeze
  XSL = "#{ASSETS_DIR}/iso.international-standard.xsl".freeze

  it "generates a PDF" do
    FileUtils.rm_f DROP
    FileUtils.mkdir_p ASSETS_DIR

    generator = Metanorma::Output::XslfoPdf.new

    generator.convert(INPUT, OUTPUT, XSL)
    expect(File.exist?(OUTPUT)).to be true
  end

  it "handle absolute path" do
    FileUtils.rm_f DROP
    FileUtils.mkdir_p ASSETS_DIR

    generator = Metanorma::Output::XslfoPdf.new

    generator.convert(File.join(Dir.pwd, INPUT), File.join(Dir.pwd, OUTPUT),
                      XSL)
    expect(File.exist?(File.join(Dir.pwd, OUTPUT))).to be true
  end

  #   it "handle url as input" do
  #     FileUtils.rm_f DROP
  #     FileUtils.mkdir_p ASSETS_DIR
  #
  #     generator = Metanorma::Output::XslfoPdf.new
  #
  #     generator.convert("file://#{File.join(Dir.pwd, INPUT)}", OUTPUT, XSL)
  #     expect(File.exist?(OUTPUT)).to be true
  #   end

  it "Missing input path" do
    generator = Metanorma::Output::XslfoPdf.new
    expect { generator.convert("random.html", "random.pdf", XSL) }
      .to raise_error
  end

  it "Path with spaces" do
    dir = File.join(ASSETS_DIR, "dir with path")
    input = File.join(dir, "a.xml")
    output = File.join(dir, "a.pdf")
    FileUtils.rm_f [output]
    FileUtils.mkdir_p dir
    generator = Metanorma::Output::XslfoPdf.new

    generator.convert(input, output, XSL)

    expect(File.exist?(output)).to be true
  end
end
