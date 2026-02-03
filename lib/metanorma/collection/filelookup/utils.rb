module Metanorma
  class Collection
    class FileLookup
      # Also parse all ids in doc (including ones which won't be xref targets)
      def read_ids(xml)
        ret = {}
        xml.traverse do |x|
          x.text? and next
          x["id"] and ret[x["id"]] = true
        end
        ret
      end

      # map locality type and label (e.g. "clause" "1") to id = anchor for
      # a document
      # Note: will only key clauses, which have unambiguous reference label in
      # locality. Notes, examples etc with containers are just plunked against
      # UUIDs, so that their IDs can at least be registered to be tracked
      # as existing.
      def read_anchors(xml)
        xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.i18n,
                                  { locale: @locale })
        xrefs.parse xml
        xrefs.get.each_with_object({}) do |(k, v), ret|
          read_anchors1(k, v, ret)
        end
      end

      def read_anchors1(key, val, ret)
        val[:type] ||= "clause"
        ret[val[:type]] ||= {}
        index = if val[:container] || val[:label].nil? || val[:label].empty?
                  UUIDTools::UUID.random_create.to_s
                else val[:label].gsub(%r{<[^>]+>}, "")
                end
        ret[val[:type]][index] = key
        v = val[:value] and ret[val[:type]][v.gsub(%r{<[^>]+>}, "")] = key
      end

      def anchors_lookup(anchors)
        anchors.values.each_with_object({}) do |v, m|
          v.each_value { |v1| m[v1] = true }
        end
      end

      # return citation url for file
      # @param doc [Boolean] I am a Metanorma document,
      # so my URL should end with html or pdf or whatever
      def url(ident, options)
        data = get(ident)
        data[:url] || targetfile(data, options)[1]
      end

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
