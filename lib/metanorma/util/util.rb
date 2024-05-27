module Metanorma
  module Util
    class << self
      def log(message, type = :info)
        log_types = Metanorma.configuration.logs.map(&:to_s) || []

        if log_types.include?(type.to_s)
          puts(message)
        end

        if type == :fatal
          exit(1)
        end
      end

      # dependency ordering
      def sort_extensions_execution_ord(ext)
        case ext
        when :xml then 0
        when :rxl then 1
        when :presentation then 2
        else
          99
        end
      end

      def sort_extensions_execution(ext)
        ext.sort do |a, b|
          sort_extensions_execution_ord(a) <=> sort_extensions_execution_ord(b)
        end
      end

      def recursive_string_keys(hash)
        case hash
        when Hash then hash.map do |k, v|
                         [k.to_s, recursive_string_keys(v)]
                       end.to_h
        when Enumerable then hash.map { |v| recursive_string_keys(v) }
        else
          hash
        end
      end

      def gather_bibitems(xml)
        xml.xpath("//xmlns:bibitem[@id]").each_with_object({}) do |b, m|
          if m[b["id"]]
            b.remove
            next # we can't update duplicate bibitem, processing updates wrong one
          else
            m[b["id"]] = b
          end
        end
      end

      def gather_bibitemids(xml)
        xml.xpath("//*[@bibitemid]").each_with_object({}) do |e, m|
          /^semantic__/.match?(e.name) and next
          m[e["bibitemid"]] ||= []
          m[e["bibitemid"]] << e
        end
      end

      def gather_citeases(xml)
        xml.xpath("//*[@citeas]").each_with_object({}) do |e, m|
          /^semantic__/.match?(e.name) and next
          m[e["citeas"]] ||= []
          m[e["citeas"]] << e
        end
      end

      def add_suffix_to_attributes(doc, suffix, tag_name, attr_name, isodoc)
        (suffix.nil? || suffix.empty?) and return
        doc.xpath(isodoc.ns("//#{tag_name}[@#{attr_name}]")).each do |elem|
          a = elem.attributes[attr_name].value
          /_#{suffix}$/.match?(a) or
            elem.attributes[attr_name].value = "#{a}_#{suffix}"
        end
      end

      def hash_key_detect(directives, key, variable)
        c = directives.detect { |x| x.key == key } or
          return variable
        c.value
      end

      def rel_path_resolve(dir, path)
        path.nil? and return path
        path.empty? and return path
        p = Pathname.new(path)
        p.absolute? ? path : File.join(dir, path)
      end

      def key(ident)
        @c ||= HTMLEntities.new
        @c.decode(ident).gsub(/(\p{Zs})+/, " ")
      end

      class Dummy
        def attr(_key); end
      end

      def load_isodoc(doctype)
        x = Asciidoctor.load nil, backend: doctype.to_sym
        x.converter.html_converter(Dummy.new) # to obtain Isodoc class
      end
    end
  end
end
