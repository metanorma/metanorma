# frozen_string_literal: true

class Array
  alias orig_filter filter
end

require "metanorma/version"
require "asciidoctor"
require "metanorma/util/util"
require "metanorma/config/config"
require "metanorma/input"
require "metanorma/registry/registry"
require "metanorma/processor/processor"
require "metanorma/asciidoctor_extensions"
require "metanorma/compile/compile"
require "metanorma/collection/collection"
require "metanorma/collection/manifest/manifest"
require "metanorma/collection/renderer/renderer"
require "metanorma/collection/document/document"
require "vectory"

# Metanorma module
module Metanorma
end
