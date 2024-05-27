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
    end
  end
end
