# frozen_string_literal: true

module Metanorma
  class Compile
    # Thin adapter over the metanorma-core flavor table: canonical
    # flavor resolution (taste chains + gem loading) lives in
    # Core::Flavors — the single source of truth. Missing-gem and
    # unsupported-backend errors still route through FlavorLoader so
    # the existing SystemExit / error-log contract is preserved.
    module Flavor
      def load_flavor(stdtype)
        entry = Metanorma::Core::Flavors.find(stdtype)
        if entry&.taste?
          stdtype = entry.base_flavor
          entry = Metanorma::Core::Flavors.find(stdtype)
        end

        if entry
          load_registered_flavor(entry, stdtype)
        else
          # Unknown stdtype: fall back to FlavorLoader's gem-name
          # convention + its LoadError -> SystemExit path.
          Metanorma::Core::FlavorLoader.load_flavor(stdtype)
        end
      end

      def taste2flavor(stdtype)
        entry = Metanorma::Core::Flavors.find(stdtype)
        return entry.base_flavor if entry&.taste?

        Metanorma::Core::FlavorLoader.taste2flavor(stdtype)
      end

      private

      def load_registered_flavor(entry, stdtype)
        registry = Metanorma::Registry.instance
        return entry.name if registry.supported_backends.include?(entry.name)

        begin
          Metanorma::Util.log(
            "[metanorma] Info: Loading `#{entry.gem}` gem " \
            "for standard type `#{stdtype}`.", :info
          )
          require entry.gem
          Metanorma::Util.log(
            "[metanorma] Info: gem `#{entry.gem}` loaded.", :info
          )
        rescue LoadError => e
          Metanorma::Core::FlavorLoader.write_flavor_error_log(e, entry.gem)
        end

        return entry.name if registry.supported_backends.include?(entry.name)

        Metanorma::Core::FlavorLoader.flavor_unsupported(entry.gem, stdtype)
      end
    end
  end
end
