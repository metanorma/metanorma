module Metanorma
  class CollectionRenderer
    def docconv
      @tempfile_cache ||= []
      doctype = @doctype.to_sym
      x = Asciidoctor.load nil, backend: doctype
      x.converter.doc_converter(DocOptionsNode.new(@directives))
    end

    def concat_extract_files(filename)
      xml = Nokogiri::XML(File.read(filename, encoding: "UTF-8"), &:huge)
      docs = xml.xpath("//xmlns:doc-container").each_with_object([]) do |x, m|
        n = Nokogiri::XML::Document.new
        n.add_child(x.elements.first.remove)
        m << n
      end
      [wrapping_doc(docs.first.dup, xml), docs]
    end

    def wrapping_doc(doc, xml)
      b = doc.at("//xmlns:bibdata")
      b.replace(xml.at("//xmlns:bibdata").to_xml)
      doc.xpath("//xmlns:annex | //xmlns:preface | //xmlns:bibliography").each(&:remove)
      s = doc.at("//xmlns:sections")
      s.replace("<sections><clause id='_collection_placeholder'><p>PLACEHOLDER</p></clause></sections>")
      p = xml.at("//xmlns:prefatory-content") and s.previous = "<preface>#{p.children.to_xml}</preface>"
      p = xml.at("//xmlns:final-content") and s.previous = "<annex>#{p.children.to_xml}</annex>"
      doc.xpath("//xmlns:preface/* | //xmlns:sections/* | //xmlns:annex").each_with_index do |x, i|
        x["displayorder"] = i + 1
      end
      doc
    end

    SECTION_BREAK = '<p class="MsoNormal"><br clear="all" class="section"/></p>'.freeze
    DIV1 = '<div class="WordSection1">&#xa0;</div>'.freeze
    DIV2 = '<div class="WordSection2">&#xa0;</div>'.freeze

    def docconv_convert1(docs)
      docs.each_with_index.with_object([]) do |(d, i), m|
        conv = docconv
        conv.convert_init(d.to_xml(encoding: "UTF-8"), "xxxx", false)
        html = conv.postprocess_cleanup(conv.convert1(d, "xxx", "."))
        @tempfile_cache += conv.tempfile_cache # hold on to the temp img files
        b = Nokogiri::XML(html).at("//body")
        i == docs.size - 1 or
          b << '<p class="MsoNormal"><br clear="all" class="section"/></p>'
        m << b.children
      end
    end

    def collection_coverpages(conv, docs)
      conv.wordintropage and [DIV2, SECTION_BREAK].reverse.each do |s|
        docs.unshift(Nokogiri::XML(s).root)
      end
      conv.wordcoverpage and [DIV1, SECTION_BREAK].reverse.each do |s|
        docs.unshift(Nokogiri::XML(s).root)
      end
      docs
    end

    def docconv_convert(filename)
      pref_file, docs = concat_extract_files(filename)
      body = docconv_convert1(docs)
      collection_conv = overall_docconv_converter(body)
      collection_coverpages(collection_conv, body)
      collection_conv.convert(filename, pref_file.to_xml, false)
    end

    def overall_docconv_cover(collection_conv)
      collection_conv.wordcoverpage =
        Util::hash_key_detect(@directives, "collection-word-coverpage", nil)
      collection_conv.wordintropage =
        Util::hash_key_detect(@directives, "collection-word-intropage", nil)
    end

    def overall_docconv_converter(body)
      collection_conv = docconv
      collection_conv.options[:collection_doc] = body.map(&:to_xml).join
      overall_docconv_cover(collection_conv)

      def collection_conv.postprocess_cleanup(result)
        ret = to_xhtml(super)
        b = ret.at("//div[@id = '_collection_placeholder']")
        b.replace(@options[:collection_doc])
        from_xhtml(ret)
      end

      collection_conv
    end

    class DocOptionsNode
      def initialize(directives)
        @wordcoverpage =
          Util::hash_key_detect(directives, "document-word-coverpage",
                                @wordcoverpage)
        @wordintropage =
          Util::hash_key_detect(directives, "document-word-intropage",
                                @wordintropage)
      end

      def attr(key)
        case key
        when "wordcoverpage" then @wordcoverpage
        when "wordintropage" then @wordintropage
        end
      end
    end
  end
end
