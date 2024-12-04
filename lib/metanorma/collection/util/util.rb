module Metanorma
  class Collection
    module Util
      class << self
        def gather_bibitems(xml)
          xml.xpath("//xmlns:bibitem[@id]").each_with_object({}) do |b, m|
            if m[b["id"]]
              b.remove
              next
              # we can't update duplicate bibitem, processing updates wrong one
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

        def add_suffix_to_attrs(doc, suffix, tag_name, attr_name, isodoc)
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

        def load_isodoc(flavor, presxml: false)
          x = Asciidoctor.load nil, backend: flavor.to_sym
          if presxml
          x.converter.presentation_xml_converter(Dummy.new)
          else
          x.converter.html_converter(Dummy.new) # to obtain Isodoc class
          end
        end

        def isodoc_create(flavor, lang, script, xml, presxml: false)
        isodoc = Util::load_isodoc(flavor, presxml: presxml)
        isodoc.i18n_init(lang, script, nil) # read in internationalisation
        # TODO locale?
        isodoc.metadata_init(lang, script, nil, isodoc.i18n)
        isodoc.info(xml, nil)
        isodoc
      end
      end
    end
  end
end
