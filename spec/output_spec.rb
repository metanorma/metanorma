require_relative "spec_helper"

RSpec.describe Metanorma::Output::Pdf do
  it "generates a PDF" do
    system "rm -f a.html a.pdf"
    File.open("a.html", "w") { |f| f.write("<html><head/><body><h1>Hello</h1></body></html>") }
    generator = Metanorma::Output::Pdf.new
    generator.convert("a.html", "a.pdf")
    expect(File.exist?("a.pdf")).to be true
  end
end
