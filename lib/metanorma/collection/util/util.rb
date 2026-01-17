module Metanorma
  class Collection
    module Util
      class << self
        def anchor_id_attributes
          Metanorma::Utils::anchor_attributes(presxml: true) +
            [%w(* id), %w(* anchor), %w(link bibitemid), %w(fmt-link bibitemid)]
        end

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

        def gather_bibitemids(xml, presxml)
          xml.xpath("//*[@bibitemid]").each_with_object({}) do |e, m|
            presxml && %w(xref eref link).include?(e.name) and next
            m[e["bibitemid"]] ||= []
            m[e["bibitemid"]] << e
          end
        end

        def gather_citeases(xml, presxml)
          xml.xpath("//*[@citeas]").each_with_object({}) do |e, m|
            presxml && %w(xref eref link).include?(e.name) and next
            k = key(e["citeas"])
            m[k] ||= []
            m[k] << e
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

        def hide_refs(docxml)
          p = "//xmlns:references[xmlns:bibitem]"\
            "[not(./xmlns:bibitem[not(@hidden) or @hidden = 'false'])]"
          docxml.xpath(p).each do |f|
            f["hidden"] = "true"
          end
        end

        def key(ident)
          @c ||= HTMLEntities.new
          @c.decode(ident).gsub(/(\p{Zs})+/, " ")
        end

        def taste2flavor(taste)
          tastes = Metanorma::TasteRegister.instance.aliases
          tastes[taste.to_sym] and taste = tastes[taste.to_sym]
          taste
        end

        def taste2isodoc_attrs(taste, format)
          tastes = Metanorma::TasteRegister.instance.aliases
          tastes[taste.to_sym] or return {}
          Metanorma::TasteRegister.isodoc_attrs(taste.to_sym, format)
        end

        def taste2coverpage_pdf_portfolio(taste)
          tastes = Metanorma::TasteRegister.instance.aliases
          tastes[taste.to_sym] or return nil
          taste = Metanorma::TasteRegister.instance.get(taste.to_sym)
          ret = taste.config.base_override&.filename_attributes
            &.coverpage_pdf_portfolio or return
          File.join(taste.directory, ret)
        end

        # update relative URLs, url(#...), in CSS in @style attrs (including SVG)
        def url_in_css_styles(doc, document_suffix)
          doc.xpath("//*[@style]").each do |s|
            s["style"] = url_in_css_styles1(s["style"], document_suffix)
          end
          doc.xpath("//i:svg//i:style", "i" => "http://www.w3.org/2000/svg")
            .each do |s|
              s.children = url_in_css_styles1(s.text, document_suffix)
          end
        end

        def url_in_css_styles1(style, document_suffix)
          style.gsub(%r{url\(#([^()]+)\)}, "url(#\\1_#{document_suffix})")
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
          isodoc.xref_init(lang, script, nil, isodoc.i18n, {})
          isodoc.xrefs.klass.meta = isodoc.meta
          isodoc.info(xml, nil)
          isodoc
        end

        def asciidoc_dummy_header
          <<~DUMMY
            = X
            A

          DUMMY
        end

        def nokogiri_to_temp(xml, filename, suffix)
          file = Tempfile.new([filename, suffix])
          file.write(xml.to_xml(indent: 0))
          file.close
          [file, file.path]
        end
      end
    end
  end
end
