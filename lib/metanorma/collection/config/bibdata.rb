require "relaton"
require "shale"

module Metanorma
  class Collection
    module Config
      class Bibdata < ::Shale::Mapper
        model ::RelatonBib::BibliographicItem
      end
    end
  end
end
