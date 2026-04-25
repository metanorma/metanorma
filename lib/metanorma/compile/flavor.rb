# frozen_string_literal: true

module Metanorma
  class Compile
    module Flavor
      def load_flavor(stdtype)
        Metanorma::Core::FlavorLoader.load_flavor(stdtype)
      end

      def taste2flavor(stdtype)
        Metanorma::Core::FlavorLoader.taste2flavor(stdtype)
      end

      def stdtype2flavor_gem(stdtype)
        Metanorma::Core::FlavorLoader.stdtype2flavor_gem(stdtype)
      end
    end
  end
end
