require_relative "../spec_helper"
require "metanorma/plugin/lutaml"

RSpec.describe "lutaml XMI cache release at the compile phase boundary" do
  it "flushes the retained XMI graphs once conversion completes" do
    cache = Metanorma::Plugin::Lutaml::XmiCache::XMI_PARSE_CACHE
    cache.clear
    xmi = File.expand_path("fixtures/lutaml/minimal_test.xmi", __dir__)

    first = cache.fetch_drop(xmi)

    doc = File.join(Dir.mktmpdir, "xmi_flush.adoc")
    File.write(doc, <<~ASCIIDOC)
      = Cache flush probe
      :docnumber: 1
      :revdate: 2026-11-01
      :language: en
      :mn-output-extensions: xml

      Text.
    ASCIIDOC
    Metanorma::Compile.new.compile(doc, type: :standoc, extension_keys: [:xml])

    second = cache.fetch_drop(xmi)
    # re-parsed rather than served from the cache: the flush happened.
    # On stacks whose metanorma-standoc also flushes at the converter
    # level (git-main), this is a duplicate of release_lutaml_caches;
    # released standoc does not flush, so the compile-level boundary is
    # what guarantees the release there.
    expect(second).not_to equal(first)
  end
end
