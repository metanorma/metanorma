module Metanorma
  class Collection
    class FileLookup
      def anchors_lookup(anchors)
        anchors.values.each_with_object({}) do |v, m|
          v.each_value { |v1| m[v1] = true }
        end
      end

      # are references to the file to be linked to a file in the collection,
      # or externally? Determines whether file suffix anchors are to be used
      def url?(ident)
        data = get(ident) or return false
        data[:url]
      end

      # Normalise an identifier to its @files hash key: decode entities, squeeze
      # whitespace, and strip a leading "metanorma-collection " prefix. Distinct
      # from Util::key, which does NOT strip that prefix.
      def entry_key(ident)
        @c.decode(ident).gsub(/(\p{Zs})+/, " ")
          .sub(/^metanorma-collection /, "")
      end

      def keys
        @files.keys
      end

      def get(ident, attr = nil)
        if attr then @files[entry_key(ident)][attr]
        else @files[entry_key(ident)]
        end
      end

      def set(ident, attr, value)
        @files[entry_key(ident)][attr] = value
      end

      def each
        @files.each
      end

      def each_with_index
        @files.each_with_index
      end

      def ns(xpath)
        @isodoc.ns(xpath)
      end
    end
  end
end
