require "relaton"
require "lutaml/model"

module Metanorma
  class Collection
    module Config
      class Bibdata < ::Lutaml::Model::Serializable
        model ::Relaton::Bib::ItemData
      end
    end
  end
end
