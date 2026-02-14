module Metanorma
  class Collection
    module Util
      class DisambigFiles
        def initialize
          @seen_filenames = []
        end

        def strip_root(name)
          name.sub(%r{^(\./)?(\.\./)+}, "")
        end

        def source2dest_filename(name, disambig: true, preserve_dirs: false)
          n = strip_root(name)
          dir = preserve_dirs ? "." : File.dirname(n)
          base = preserve_dirs ? n : File.basename(n)
          disambig && @seen_filenames.include?(base) and
            base = disambiguate_filename(base)
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
end
