require 'shale'

module Metanorma
  module CollectionConfig
    class CompileOptions < ::Shale::Mapper
      attribute :no_install_fonts, ::Shale::Type::Boolean, default: -> { true }
      attribute :agree_to_terms, ::Shale::Type::Boolean, default: -> { true }
    end
  end
end
