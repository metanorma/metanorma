# frozen_string_literal: true

module Metanorma
  class Compile
    module Validator
      def validate_options!(options)
        validate_type!(options)
        validate_format!(options)
      end

      def validate_type!(options)
        options[:type] or
          Util.log("[metanorma] Error: Please specify a standard type: "\
                   "#{@registry.supported_backends}.", :fatal)
        stdtype = options[:type].to_sym
        load_flavor(stdtype)
      end

      def validate_format!(options)
        options[:format] == :asciidoc or
          Util.log("[metanorma] Error: Only source file format currently "\
                   "supported is 'asciidoc'.", :fatal)
      end
    end
  end
end
