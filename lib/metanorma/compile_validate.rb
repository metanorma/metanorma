module Metanorma
  class Compile
    def validate_options(options)
      validate_type(options)
      validate_format(options)
    end

    def validate_type(options)
      unless options[:type]
        Util.log("[metanorma] Error: Please specify a standard type: "\
                 "#{@registry.supported_backends}.", :fatal)
      end
      stdtype = options[:type].to_sym
      load_flavor(stdtype)
    end

    def validate_format(options)
      unless options[:format] == :asciidoc
        Util.log("[metanorma] Error: Only source file format currently "\
                 "supported is 'asciidoc'.", :fatal)
      end
    end

    private

    def load_flavor(stdtype)
      flavor = "metanorma-#{stdtype}"
      unless @registry.supported_backends.include? stdtype
        Util.log("[metanorma] Info: Loading `#{flavor}` gem "\
                 "for standard type `#{stdtype}`.", :info)
      end
      require_flavor(flavor, stdtype)
      unless @registry.supported_backends.include? stdtype
        Util.log("[metanorma] Error: The `#{flavor}` gem "\
                 "still doesn't support `#{stdtype}`. Exiting.", :fatal)
      end
    end

    def require_flavor(flavor, stdtype)
      require flavor
      Util.log("[metanorma] Info: gem `#{flavor}` loaded.", :info)
    rescue Gem::ConflictError
      Util.log("[metanorma] Error: Couldn't resolve dependencies for "\
               "`metanorma-#{stdtype}`, Please add it to your Gemfile "\
               "and run bundle install first", :fatal)
    rescue LoadError
      msg = <<~MSG
        [metanorma] Error: loading gem `#{flavor}` failed. Exiting.

        Troubleshooting:
        1. If you are using metanorma via bundler/ruby, make sure that your
           Gemfile contains a line:
             gem "metanorma-#{stdtype}"

        2. If you are using brew/choco/snap packages, please report an issue
           to https://github.com/metanorma/packed-mn/issues/new"
      MSG
      Util.log(msg, :fatal)
    end
  end
end
