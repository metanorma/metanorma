# frozen_string_literal: true

require "moxml"
require "relaton"
require "relaton/bib"

module Metanorma
  class Collection
    module Config
      # Collection bibdata ingestion through relaton's library surface.
      #
      # Mirrors the flavor dispatch of the relaton Cli entry points
      # (cli.rb parse_xml, YAMLConvertor convert_single_file): the
      # processor is named by the first docidentifier's type, else by the
      # leading word of its text. The long-term home for this logic is a
      # relaton library-level API (follow-up issue, not filed from here);
      # metanorma must not call the user-facing Cli layer.
      module BibdataParser
        class << self
          # @param xml [String] serialized bibdata or bibitem XML
          # @return [Relaton::Bib::ItemData, nil] nil when the source is not
          #   parseable XML
          def from_xml(xml)
            return unless xml

            doc = Moxml.new.parse(xml)
            plain = without_namespaces(doc)
            if (processor = processor_for_xml(doc))
              processor.from_xml(plain)
            else
              # No-flavor fallback: unparseable sources degrade to a nil
              # bibdata, as in the mirrored Cli method.
              Relaton::Bib::Item.from_xml(plain) rescue nil
            end
          rescue Moxml::ParseError
            nil
          end

          # @param content [Hash] bibdata in YAML form
          # @return [Relaton::Bib::ItemData]
          def from_yaml(content)
            yaml = content.to_yaml
            if (processor = processor_for_yaml(content))
              begin
                processor.from_yaml(yaml)
              rescue RuntimeError
                Relaton::Bib::Item.from_yaml(yaml)
              end
            else
              Relaton::Bib::Item.from_yaml(yaml)
            end
          end

          private

          # The processor named by the first docidentifier's type, else by
          # the first word of its text.
          def processor_for_xml(doc)
            docid = doc.xpath("//*[local-name()='docidentifier']").first
            proc = get_proc(docid)
            return proc if proc

            Relaton::Db::Registry.instance
              .by_type(docid&.text&.match(/^\w+/)&.to_s)
          end

          def get_proc(docid)
            type = docid&.[]("type")
            return unless type

            Relaton::Db::Registry.instance.by_type(type)
          end

          # The processor named by `ext.flavor`, else by the first
          # docidentifier's type / leading word of its content.
          def processor_for_yaml(content)
            flavor = content.dig("ext", "flavor") ||
              yaml_doctype(content["docidentifier"])
            return unless flavor

            Relaton::Db::Registry.instance.by_type(flavor)
          end

          def yaml_doctype(docid)
            did = docid.is_a?(Array) ? docid.fetch(0) : docid
            return unless did

            did["type"] || did.fetch("content")&.match(/^\w+/)&.to_s
          end

          # The root element as XML, with every element and attribute in no
          # namespace (`xml:` attributes keep their prefix). The lutaml-model
          # mappings are namespace-free: they skip a prefixed element, and a
          # nested `relation/bibitem` in a default namespace raises in
          # lutaml-model 0.8.175. Moxml cannot drop a namespace in place, so
          # this builds a copy. (Mirror of relaton cli.rb without_namespaces.)
          def without_namespaces(doc)
            plain = Moxml.new.create_document
            plain.add_child plain_element(plain, doc.root)
            plain.root.to_xml
          end

          def plain_element(doc, src)
            elm = doc.create_element(src.name)
            # An attribute in no namespace wins over a prefixed one of the
            # same local name (`type` over `a:type`).
            src.attributes.sort_by { |a| a.namespace ? 0 : 1 }.each do |attr|
              elm[plain_name(attr)] = attr.value
            end
            src.children.each { |child| elm.add_child plain_node(doc, child) }
            elm
          end

          # The local name; an `xml:` attribute keeps its prefix.
          def plain_name(attr)
            attr.namespace&.prefix == "xml" ? "xml:#{attr.name}" : attr.name
          end

          # An entity reference (`&nbsp;`) stays as its text: lutaml-model
          # cannot read an entity it has no declaration for. A processing
          # instruction becomes an empty text.
          def plain_node(doc, src)
            case src
            when Moxml::Element then plain_element(doc, src)
            when Moxml::Cdata then doc.create_cdata(src.content)
            when Moxml::Text then doc.create_text(src.content)
            when Moxml::Comment then doc.create_comment(src.content)
            when Moxml::EntityReference then doc.create_text("&#{src.name};")
            else doc.create_text("")
            end
          end
        end
      end
    end
  end
end
