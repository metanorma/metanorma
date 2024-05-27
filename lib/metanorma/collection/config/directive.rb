module Metanorma
  class Collection
    module Config
      class Directive < ::Shale::Mapper
        attribute :key, ::Shale::Type::String
        attribute :value, ::Shale::Type::String
      end
    end
  end
end
