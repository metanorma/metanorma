require "lutaml/model"

module Metanorma
  class Collection
    module Config
      class CompileOptions < ::Lutaml::Model::Serializable
        attribute :install_fonts, ::Lutaml::Model::Type::Boolean,
                  default: -> { false }
        attribute :agree_to_terms, ::Lutaml::Model::Type::Boolean,
                  default: -> { true }
      end
    end
  end
end
