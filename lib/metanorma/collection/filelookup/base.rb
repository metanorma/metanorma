module Metanorma
  class Collection
    class FileLookup
      # are references to the file to be linked to a file in the collection,
      # or externally? Determines whether file suffix anchors are to be used
      def url?(ident)
        data = get(ident) or return false
        data[:url]
      end

      def key(ident)
        @c.decode(ident).gsub(/(\p{Zs})+/, " ")
          .sub(/^metanorma-collection /, "")
      end

      def keys
        @files.keys
      end

      def get(ident, attr = nil)
        if attr then @files[key(ident)][attr]
        else @files[key(ident)]
        end
      end

      def set(ident, attr, value)
        @files[key(ident)][attr] = value
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
