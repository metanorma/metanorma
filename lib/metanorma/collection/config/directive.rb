module Metanorma
  class Collection
    module Config
      class Directive < ::Lutaml::Model::Serializable
        attribute :key, ::Lutaml::Model::Type::String
        attribute :value, ::Lutaml::Model::Type::String
      end
    end
  end
end
