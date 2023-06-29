require_relative "spec_helper"
require "fileutils"
require "fontist"

RSpec.describe Metanorma::Compile do
  # needs to be run before collection_spec.rb for it to work
  it "aborts if include error" do
    require "metanorma-iso"
    input = <<~INPUT
      = Document title
      Author
      :docfile: test.adoc
      :nodoc:

      include::common/common-sections/00-abstract.adoc[]

    INPUT
    expect do
      Metanorma::Input::Asciidoc.new
        .process(input, "test.adoc", :iso)
    end.to raise_error(SystemExit)
  rescue SystemExit
  end
end
