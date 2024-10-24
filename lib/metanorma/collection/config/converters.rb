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
          require "debug"; binding.b
          model.bibdata = node # Relaton::Cli.parse_xml(node.content)
        end

        def bibdata_to_xml(model, parent, doc)
          require "debug"; binding.b
          b = model.bibdata or return
          elem = b.to_xml(bibdata: true, date_format: :full)
          doc.add_element(parent, elem)
        end

        def nop_to_yaml(model, doc); end
      end
    end
  end
end
