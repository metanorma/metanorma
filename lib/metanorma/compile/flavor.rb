# frozen_string_literal: true

module Metanorma
  class Compile
    # Thin adapter over the metanorma-core flavor table: canonical
    # flavor resolution (taste chains + gem loading) lives in
    # Core::Flavors — the single source of truth.
    module Flavor
      def load_flavor(stdtype)
        entry = Metanorma::Core::Flavors.resolve(stdtype)
        entry&.name || begin
          require "metanorma-#{stdtype}"
          stdtype.to_sym
        end
      end

      def taste2flavor(stdtype)
        entry = Metanorma::Core::Flavors.find(stdtype)
        return entry.base_flavor if entry&.taste?

        Metanorma::Core::FlavorLoader.taste2flavor(stdtype)
      end
    end
  end
end
