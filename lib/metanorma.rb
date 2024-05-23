# frozen_string_literal: true

class Array
  alias orig_filter filter
end

require "metanorma/version"
require "asciidoctor"
require "metanorma/util/util"
require "metanorma/util/config"
require "metanorma/input"
require "metanorma/registry/registry"
require "metanorma/processor/processor"
require "metanorma/asciidoctor_extensions"
require "metanorma/compile/compile"
require "metanorma/collection/collection"
require "metanorma/collection_manifest/collection_manifest"
require "metanorma/collection_render/collection_renderer"
require "metanorma/collection_document/document"
require "vectory"

# Metanorma module
module Metanorma
end
