require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Output::Pdf do
  it "generates a PDF from HTML" do
    FileUtils.rm_f %w(a.html a.pdf)
    File.write("a.html", "<html><head/><body><h1>Hello</h1></body></html>")
    generator = Metanorma::Output::Pdf.new
    generator.convert("a.html", "a.pdf")
    expect(File.exist?("a.pdf")).to be true
  end

  it "handle absolute path" do
    FileUtils.rm_f %w(a.html a.pdf)
    File.write("a.html", "<html><head/><body><h1>Hello</h1></body></html>")
    generator = Metanorma::Output::Pdf.new
    generator.convert(File.join(Dir.pwd, "a.html"), File.join(Dir.pwd, "a.pdf"))
    expect(File.exist?(File.join(Dir.pwd, "a.pdf"))).to be true
  end

  it "handle url as input" do
    FileUtils.rm_f %w(a.html a.pdf)
    File.write("a.html", "<html><head/><body><h1>Hello</h1></body></html>")
    generator = Metanorma::Output::Pdf.new
    generator.convert("file://#{File.join(Dir.pwd, "a.html")}", "a.pdf")
    expect(File.exist?("a.pdf")).to be true
  end

  it "Missing input path" do
    generator = Metanorma::Output::Pdf.new
    expect { generator.convert("random.html", "random.pdf") }.to raise_error
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
