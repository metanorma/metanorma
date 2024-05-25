require 'relaton'
require 'shale'

module Metanorma
  module CollectionConfig

    class Bibdata < ::Shale::Mapper
      model ::RelatonBib::BibliographicItem
    end
  end
end
