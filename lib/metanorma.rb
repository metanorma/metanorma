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
# The collection renderer drives Relaton::Render directly, and isodoc's
# render wiring reaches the gem through sub-paths that do not define the
# Unrenderable marker its render_all rescue raises (the same break
# isodoc#882/#883 fixed on the isodoc side); load the full entry so the
# constant exists for every consumer of this library.
require "relaton-render"

# Metanorma module
module Metanorma
end
