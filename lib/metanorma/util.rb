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

    # dependency ordering
    def self.sort_extensions_execution_ord(ext)
      case ext
      when :xml then 0
      when :rxl then 1
      when :presentation then 2
      else
        99
      end
    end

    def self.sort_extensions_execution(ext)
      ext.sort do |a, b|
        sort_extensions_execution_ord(a) <=> sort_extensions_execution_ord(b)
      end
    end

    def self.recursive_string_keys(hash)
      case hash
      when Hash then hash.map { |k, v| [k.to_s, recursive_string_keys(v)] }.to_h
      when Enumerable then hash.map { |v| recursive_string_keys(v) }
      else
        hash
      end
    end

    def self.gather_bibitems(xml)
      xml.xpath("//xmlns:bibitem[@id]").each_with_object({}) do |b, m|
        m[b["id"]] = b
      end
    end

    def self.gather_bibitemids(xml)
      xml.xpath("//*[@bibitemid]").each_with_object({}) do |e, m|
        m[e["bibitemid"]] ||= []
        m[e["bibitemid"]] << e
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
