# frozen_string_literal: true

class Array
  alias orig_filter filter
end

require "metanorma/version"
require "asciidoctor"
require "metanorma/util"
require "metanorma/config"
require "metanorma/input"
require "metanorma/registry"
require "metanorma/processor"
require "metanorma/asciidoctor_extensions"
require "metanorma/compile"
require "metanorma/collection"
require "metanorma/collection_renderer"
require "metanorma/document"
require "vectory"

# Metanorma module
module Metanorma
end
