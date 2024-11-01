require "lutaml/model"

module Metanorma
  class Collection
    module Config
      class CompileOptions < ::Lutaml::Model::Serializable
        attribute :install_fonts, :boolean, default: -> { false }
        attribute :agree_to_terms, :boolean, default: -> { true }
      end
    end
  end
end
