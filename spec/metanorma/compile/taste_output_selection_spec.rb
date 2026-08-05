require "spec_helper"

# Taste-aware output selection in the compile driver (metanorma-core#12): a
# taste-declared document-model format (e.g. the OIML taste's :oimlsts) becomes
# selectable, gets its suffix, and picks its presentation/semantic leg, and the
# active taste is carried into isodoc options for the taste-aware Processor.
RSpec.describe "Metanorma::Compile taste-aware output selection" do
  # Real stand-in processor (no mocking library): only the two methods the
  # helpers call.
  let(:processor) do
    Class.new do
      def output_formats = { html: "html", xml: "xml" }
      def use_presentation_xml(ext) = ext == :html
    end.new
  end

  let(:compile) do
    Metanorma::Compile.allocate.tap do |c|
      c.instance_variable_set(:@processor, processor)
    end
  end

  let(:register) { Metanorma::TasteRegister.instance }

  around do |example|
    hooks = register.instance_variable_get(:@transformer_hooks)&.dup
    specs = register.instance_variable_get(:@transformer_specs)&.dup
    register.register_document_transformers(:widget) do
      { widgetsts: { suffix: "widget.sts.xml", presentation: true } }
    end
    example.run
  ensure
    register.instance_variable_set(:@transformer_hooks, hooks)
    register.instance_variable_set(:@transformer_specs, specs)
  end

  it "merges a taste's format suffix into the effective output formats" do
    fmts = compile.send(:effective_output_formats, supplied_type: :widget)
    expect(fmts[:widgetsts]).to eq("widget.sts.xml")
  end

  it "keeps the processor's own formats" do
    fmts = compile.send(:effective_output_formats, supplied_type: :widget)
    expect(fmts[:html]).to eq("html")
  end

  it "offers no taste format when no taste is active" do
    expect(compile.send(:effective_output_formats, {})).not_to have_key(:widgetsts)
  end

  it "picks the presentation leg from the taste spec's :presentation flag" do
    expect(compile.send(:uses_presentation_xml?, :widgetsts, supplied_type: :widget))
      .to be(true)
  end

  it "carries :supplied_type into isodoc options" do
    ret = {}
    compile.send(:copy_isodoc_options_attrs, { supplied_type: :widget }, ret)
    expect(ret[:supplied_type]).to eq(:widget)
  end
end
