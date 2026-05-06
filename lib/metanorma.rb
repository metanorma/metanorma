# frozen_string_literal: true

class Array
  alias orig_filter filter
end

require "metanorma/version"
require "metanorma-core"
require "metanorma/compile/compile"
require "metanorma/collection/collection"
require "metanorma/collection/manifest/manifest"
require "metanorma/collection/renderer/renderer"
require "metanorma/collection/document/document"
require "vectory"

# Metanorma module
module Metanorma
end
