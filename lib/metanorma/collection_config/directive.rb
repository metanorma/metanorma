module Metanorma
  module CollectionConfig
    class Directive < ::Shale::Mapper
      attribute :key, ::Shale::Type::String
      attribute :value, ::Shale::Type::String
    end
  end
end
