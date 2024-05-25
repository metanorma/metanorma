require "relaton-cli"

module Metanorma
  module CollectionConfig
    module Converters
      def bibdata_from_yaml(model, value)
        model.bibdata = Relaton::Cli::YAMLConvertor.convert_single_file(value)
      end

      def bibdata_to_yaml(model, doc)
        doc["bibdata"] = model.bibdata.to_yaml
      end

      def bibdata_from_xml(model, node)
        model.bibdata = Relaton::Cli.parse_xml(node.content)
      end

      def bibdata_to_xml(model, parent, doc)
        b = model.bibdata or return
        elem = b.to_xml(bibdata: true, date_format: :full)
        doc.add_element(parent, elem)
      end
    end
  end
end
