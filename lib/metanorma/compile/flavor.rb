# frozen_string_literal: true

module Metanorma
  class Compile
    module Flavor
      # Load the flavor gem for the given standard type
      # @param stdtype [Symbol] the standard type
      # @return [void]
      def load_flavor(stdtype)
        stdtype = stdtype.to_sym
        flavor = stdtype2flavor_gem(stdtype)
        @registry.supported_backends.include? stdtype or
          Util.log("[metanorma] Info: Loading `#{flavor}` gem "\
                   "for standard type `#{stdtype}`.", :info)
        require_flavor(flavor)
        @registry.supported_backends.include? stdtype or
          Util.log("[metanorma] Error: The `#{flavor}` gem does not "\
                   "support the standard type #{stdtype}. Exiting.", :fatal)
      end

      # Convert the standard type to the flavor gem name
      # @param stdtype [Symbol] the standard type
      # @return [String] the flavor gem name
      def stdtype2flavor_gem(stdtype)
        "metanorma-#{stdtype}"
      end

      private

      def require_flavor(flavor)
        require flavor
        Util.log("[metanorma] Info: gem `#{flavor}` loaded.", :info)
      rescue LoadError => e
        error_log = "#{Date.today}-error.log"
        File.write(error_log, e)

        msg = <<~MSG
          Error: #{e.message}
          Metanorma has encountered an exception.

          If this problem persists, please report this issue at the following link:

          * https://github.com/metanorma/metanorma/issues/new

          Please attach the #{error_log} file.
          Your valuable feedback is very much appreciated!

          - The Metanorma team
        MSG
        Util.log(msg, :fatal)
      end
    end
  end
end
