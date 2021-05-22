module Metanorma
  module Util
    def self.log(message, type = :info)
      log_types = Metanorma.configuration.logs.map(&:to_s) || []

      if log_types.include?(type.to_s)
        puts(message)
      end

      if type == :fatal
        exit(1)
      end
    end

    def self.source2dest_filename(name)
      name.sub(%r{^(\./)?(\.\./)+}, "")
    end
  end
end
