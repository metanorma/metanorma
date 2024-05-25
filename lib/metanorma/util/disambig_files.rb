module Metanorma
  module Util
    class DisambigFiles
      def initialize
        @seen_filenames = []
      end

      def strip_root(name)
        name.sub(%r{^(\./)?(\.\./)+}, "")
      end

      def source2dest_filename(name, disambig = true)
        n = strip_root(name)
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
