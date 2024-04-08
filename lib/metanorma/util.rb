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
        if m[b["id"]]
          b.remove
          next # we can't update duplicate bibitem, processing updates wrong one
        else
          m[b["id"]] = b
        end
      end
    end

    def self.gather_bibitemids(xml)
      xml.xpath("//*[@bibitemid]").each_with_object({}) do |e, m|
        /^semantic__/.match?(e.name) and next
        m[e["bibitemid"]] ||= []
        m[e["bibitemid"]] << e
      end
    end

    def self.gather_citeases(xml)
      xml.xpath("//*[@citeas]").each_with_object({}) do |e, m|
        /^semantic__/.match?(e.name) and next
        m[e["citeas"]] ||= []
        m[e["citeas"]] << e
      end
    end

    def self.add_suffix_to_attributes(doc, suffix, tag_name, attr_name, isodoc)
      (suffix.nil? || suffix.empty?) and return
      doc.xpath(isodoc.ns("//#{tag_name}[@#{attr_name}]")).each do |elem|
        a = elem.attributes[attr_name].value
        /_#{suffix}$/.match?(a) or
          elem.attributes[attr_name].value = "#{a}_#{suffix}"
      end
    end




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
