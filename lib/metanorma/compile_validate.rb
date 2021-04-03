module Metanorma
  class Compile
    def validate_type(options)
      unless options[:type]
        Util.log("[metanorma] Error: Please specify a standard type: "\
                 "#{@registry.supported_backends}.", :error)
        return nil
      end
      stdtype = options[:type].to_sym
      metanorma_flavor = "metanorma-#{stdtype}"
      unless @registry.supported_backends.include? stdtype
        Util.log("[metanorma] Info: Loading `#{metanorma_flavor}` gem "\
                 "for standard type `#{stdtype}`.", :info)
      end
      begin
        require "metanorma-#{stdtype}"
        Util.log("[metanorma] Info: gem `#{metanorma_flavor}` loaded.", :info)
      rescue Gem::ConflictError
        Util.log("[metanorma] Error: Couldn't resolve dependencies for "\
                 "`metanorma-#{stdtype}`, Please add it to your Gemfile "\
                 "and run bundle install first", :error)
        return false
      rescue LoadError
        Util.log("[metanorma] Error: loading gem `#{metanorma_flavor}` "\
                 "failed. Exiting.", :error)
        return false
      end
      unless @registry.supported_backends.include? stdtype
        Util.log("[metanorma] Error: The `#{metanorma_flavor}` gem "\
                 "still doesn't support `#{stdtype}`. Exiting.", :error)
        return false
      end
      true
    end

    def validate_format(options)
      unless options[:format] == :asciidoc
        Util.log("[metanorma] Error: Only source file format currently "\
                 "supported is 'asciidoc'.", :error)
        return false
      end
      true
    end
  end
end
