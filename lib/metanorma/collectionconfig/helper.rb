module Metanorma
  class Collection
  end
end

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

    def nop(model, value); end
  end

  class CompileOptions < ::Shale::Mapper
    attribute :no_install_fonts, ::Shale::Type::Boolean, default: -> { true }
    attribute :agree_to_terms, ::Shale::Type::Boolean, default: -> { true }
  end

  class Bibdata < ::Shale::Mapper
    model ::RelatonBib::BibliographicItem
  end

  class Directive < ::Shale::Mapper
    attribute :key, ::Shale::Type::String
    attribute :value, ::Shale::Type::String
  end
end
