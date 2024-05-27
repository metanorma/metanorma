require "shale"

module Metanorma
  class Collection
    module Config
      class CompileOptions < ::Shale::Mapper
        attribute :no_install_fonts, ::Shale::Type::Boolean,
                  default: -> { true }
        attribute :agree_to_terms, ::Shale::Type::Boolean, default: -> { true }
      end
    end
  end
end
