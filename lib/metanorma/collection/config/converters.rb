require "relaton-cli"

module Metanorma
  class Collection
    module Config
      module Converters
        def bibdata_from_yaml(model, value)
          value and !value.empty? or return
          model.bibdata = Relaton::Cli::YAMLConvertor.convert_single_file(value)
        end

        def bibdata_to_yaml(model, doc)
          doc["bibdata"] = model.bibdata&.to_hash
        end

        def bibdata_from_xml(model, node)
          node and
            model.bibdata = Relaton::Cli.parse_xml(node.node.adapter_node)
        end

        def bibdata_to_xml(model, parent, doc)
          b = model.bibdata or return
          elem = b.to_xml(bibdata: true, date_format: :full)
          doc.add_element(parent, elem)
        end

        def nop_to_yaml(model, doc); end

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
