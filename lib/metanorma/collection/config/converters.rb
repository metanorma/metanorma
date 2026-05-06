require "relaton/bib"
require "relaton/bib/hash_parser_v1"

module Metanorma
  class Collection
    module Config
      module Converters
        # Keys present only in 1.x YAML format — unambiguously absent in 2.x
        V1_BIBDATA_KEYS = %w[docid link biblionote].freeze

        def bibdata_from_yaml(model, value)
          (value and !value.empty?) or return
          if value.is_a?(String)
            value = YAML.safe_load_file(value,
                                        permitted_classes: [Date,
                                                            Symbol])
          end
          force_primary_docidentifier_yaml(value)
          model.bibdata = if bibdata_yaml_v1_format?(value)
                            # 1.x YAML format (docid:/link:/biblionote: present) —
                            # bridge via HashParserV1 for backward compatibility
                            h = Relaton::Bib::HashParserV1.hash_to_bib(value)
                            Relaton::Bib::ItemData.new(**h)
                          else
                            # 2.x YAML format (docidentifier:/uri:/note: keys) —
                            # parse directly with lutaml-model
                            Relaton::Bib::Item.from_yaml(value.to_yaml)
                          end
        end

        # Recursively detect 1.x-format YAML by presence of renamed keys.
        # Checks the entire nested structure so relation:/contributor: entries
        # are also detected.
        def bibdata_yaml_v1_format?(obj)
          case obj
          when Hash
            return true if (obj.keys.map(&:to_s) & V1_BIBDATA_KEYS).any?

            obj.values.any? { |v| bibdata_yaml_v1_format?(v) }
          when Array
            obj.any? { |v| bibdata_yaml_v1_format?(v) }
          else
            false
          end
        end

        def force_primary_docidentifier_yaml(value)
          case value["docid"]
          when Array
            value["docid"].empty? ||
              value["docid"].none? do |x|
                x["primary"] == "true"
              end or
              value["docid"].first["primary"] = "true"
          when Hash
            value["docid"]["primary"] ||= "true"
          end
        end

        def bibdata_to_yaml(model, doc)
          return unless model.bibdata

          doc["bibdata"] = YAML.safe_load(model.bibdata.to_yaml,
                                          permitted_classes: [Date, Symbol])
        end

        def bibdata_from_xml(model, node)
          node or return
          force_primary_docidentifier_xml(node.adapter_node)
          model.bibdata = Relaton::Cli.parse_xml(node.adapter_node)
        end

        def force_primary_docidentifier_xml(node)
          node.at("//docidentifier[@primary = 'true']") and return node
          d = node.at("//docidentifier") or return node
          d["primary"] = "true"
        end

        def bibdata_to_xml(model, parent, doc)
          b = model.bibdata or return
          elem = b.to_xml(bibdata: true, date_format: :full)
          doc.add_element(parent, elem)
        end

        def nop_to_yaml(model, doc); end
        def nop_to_xml(model, parent, doc); end

        def documents_from_xml(model, value)
          model.documents = value
            .each_with_object([]) do |b, m|
            m << b
          end
        end

        def documents_to_xml(model, parent, doc)
          documents_to_xml?(doc) or return
          b = Nokogiri::XML::Builder.new do |xml|
            xml.document do |m|
              model.collection.doccontainer(m) or return
            end
          end
          b.parent.elements.first.elements
            .each { |x| doc.add_element(parent, x) }
        end

        def documents_to_xml?(doc)
          ret = doc.parent.elements.detect do |x|
            x.name == "doc-container"
          end
          !ret
        end
      end
    end
  end
end
