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

    def load_flavor(stdtype)
      stdtype = stdtype.to_sym
      flavor = stdtype2flavor(stdtype)
      @registry.supported_backends.include? stdtype or
        Util.log("[metanorma] Info: Loading `#{flavor}` gem "\
                 "for standard type `#{stdtype}`.", :info)
      require_flavor(flavor)
      @registry.supported_backends.include? stdtype or
        Util.log("[metanorma] Error: The `#{flavor}` gem does not "\
                 "support the standard type #{stdtype}. Exiting.", :fatal)
    end

    private

    STDTYPE2FLAVOR = { plateau: "jis" }.freeze

    def stdtype2flavor(stdtype)
      flavor = STDTYPE2FLAVOR[stdtype] || stdtype
      "metanorma-#{flavor}"
    end

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
