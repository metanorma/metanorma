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

    class DisambigFiles
      def initialize
        @seen_filenames = []
      end

      def source2dest_filename(name, disambig = true)
        n = name.sub(%r{^(\./)?(\.\./)+}, "")
        dir = File.dirname(n)
        base = File.basename(n)
        if disambig && @seen_filenames.include?(base)
          base = disambiguate_filename(base)
        end
        @seen_filenames << base
        dir == "." ? base : File.join(dir, base)
      end

      def disambiguate_filename(base)
        m = /^(?<start>.+\.)(?!0)(?<num>\d+)\.(?<suff>[^.]*)$/.match(base) ||
          /^(?<start>.+\.)(?<suff>[^.]*)/.match(base) ||
          /^(?<start>.+)$/.match(base)
        i = m.names.include?("num") ? m["num"].to_i + 1 : 1
        while @seen_filenames.include? base = "#{m['start']}#{i}.#{m['suff']}"
          i += 1
        end
        base
      end
    end
  end
end
