# frozen_string_literal: true

module Metanorma
  class Compile
    # Thin adapter: taste resolution reads the core table; gem loading
    # stays on FlavorLoader so the existing SystemExit / processor-
    # registration contract is byte-identical to main.
    module Flavor
      def load_flavor(stdtype)
        Metanorma::Core::FlavorLoader.load_flavor(taste2flavor(stdtype))
      end

      def taste2flavor(stdtype)
        entry = Metanorma::Core::Flavors.find(stdtype)
        return entry.base_flavor if entry&.taste?

        Metanorma::Core::FlavorLoader.taste2flavor(stdtype)
      end

      def stdtype2flavor_gem(stdtype)
        entry = Metanorma::Core::Flavors.find(stdtype)
        return entry.gem if entry && !entry.taste?

        Metanorma::Core::FlavorLoader.stdtype2flavor_gem(stdtype)
      end
    end
  end
end
