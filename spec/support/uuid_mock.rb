# This file contains a helper method to mock random identifier generation
# (UUIDTools::UUID.random_create and Metanorma::Utils.random_uuid)
# to return an incrementing number (1, 2, 3, 4, etc.)
# each time it's called within a test.
# It also overrides the contenthash generation,
# so that the tracked GUIDs can be seen as they are used
# in generated ids and cross-references

#require 'debug'; binding.b
require "metanorma-standoc"
require "metanorma-core"

module UuidMock
  # Mock random identifier generation to return an incrementing counter
  # @return [String] the counter value
  def mock_uuid_increment
    counter = 0

    # isodoc identifiers are generated through this seam
    # (metanorma-utils)
    allow(Metanorma::Utils).to receive(:random_uuid) do
      counter += 1
      counter.to_s
    end

    # UUIDTools is still called directly by this gem's own lib code
    # (manifest config and filelookup defaults); both call sites do
    # `.random_create.to_s`, so a String return is compatible
    allow(UUIDTools::UUID).to receive(:random_create) do
      counter += 1
      counter.to_s
    end

    # Mock content hashing, preserving these GUIDs instead
    allow_any_instance_of(Metanorma::Standoc::Cleanup)
      .to receive(:contenthash_id_make) do |_instance, doc, *_args|
      ret = doc.xpath("//*[@id]").each_with_object({}) do |x, m|
        # should always be true
        m[x["id"]] = x["id"]
        x["anchor"] and m[x["anchor"]] = m[x["id"]]
      end
      warn ret
      ret
    end

  # Mock content hashing, preserving these GUIDs instead
    allow_any_instance_of(IsoDoc::PresentationXMLConvert)
      .to receive(:add_new_contenthash_id) do |_instance, doc, *args|
      ret = doc.xpath("//*[@id]").each_with_object({}) do |x, m|
        # should always be true
        m[x["id"]] = x["id"]
        args[0][x["id"]] = x["id"]
      end
      warn ret
      ret
    end
  end
end

RSpec.configure do |config|
  config.include UuidMock
end
