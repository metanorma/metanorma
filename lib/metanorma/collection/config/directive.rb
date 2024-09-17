module Metanorma
  class Collection
    module Config
      class Directive < ::Lutaml::Model::Serializable
        attribute :key, ::Lutaml::Model::Type::String
        attribute :value, ::Lutaml::Model::Type::String

        xml do
          root "directive"
          map_element "key", to: :key
          map_element "value", to: :value
        end
      end
    end
  end
end
