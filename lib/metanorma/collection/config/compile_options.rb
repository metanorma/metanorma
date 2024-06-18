require "shale"

module Metanorma
  class Collection
    module Config
      class CompileOptions < ::Shale::Mapper
        attribute :install_fonts, ::Shale::Type::Boolean,
                  default: -> { false }
        attribute :agree_to_terms, ::Shale::Type::Boolean, default: -> { true }
      end
    end
  end
end
