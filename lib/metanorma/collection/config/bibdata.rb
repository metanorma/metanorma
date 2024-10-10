require "relaton"
require "lutaml/model"

module Metanorma
  class Collection
    module Config
      class Bibdata < ::Lutaml::Model::Serializable
        model ::RelatonBib::BibliographicItem
      end
    end
  end
end
