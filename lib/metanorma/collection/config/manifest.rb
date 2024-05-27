require "shale"
require_relative "../../shale_monkeypatch"
require_relative "../../array_monkeypatch"
require_relative "converters"
require_relative "bibdata"

module Metanorma
  class Collection
    module Config
      require "shale/adapter/nokogiri"
      ::Shale.xml_adapter = ::Shale::Adapter::Nokogiri

      class Manifest < ::Shale::Mapper
        attribute :identifier, ::Shale::Type::String,
                  default: -> { UUIDTools::UUID.random_create.to_s }
        attribute :id, ::Shale::Type::String
        attribute :bibdata, Bibdata
        attribute :type, ::Shale::Type::String
        attribute :title, ::Shale::Type::String
        attribute :url, ::Shale::Type::String
        attribute :attachment, ::Shale::Type::Boolean
        attribute :sectionsplit, ::Shale::Type::Boolean
        attribute :index, ::Shale::Type::Boolean, default: -> { true }
        attribute :entry, Manifest, collection: true
        attribute :file, ::Shale::Type::String

        yaml do
          map "identifier", to: :identifier
          map "type", to: :type
          map "level", using: { from: :level_from_yaml, to: :nop }
          map "title", to: :title
          map "url", to: :url
          map "attachment", to: :attachment
          map "sectionsplit", to: :sectionsplit
          map "index", to: :index
          map "file", to: :file
          map "fileref", using: { from: :fileref_from_yaml, to: :nop }
          map "entry", to: :entry
          map "docref", using: { from: :docref_from_yaml, to: :nop }
          map "manifest", using: { from: :docref_from_yaml, to: :nop }
          map "bibdata", using: { from: :bibdata_from_yaml,
                                  to: :bibdata_to_yaml }
        end

        xml do
          root "entry"
          map_attribute "id", to: :id
          map_attribute "attachment", to: :attachment
          map_attribute "sectionsplit", to: :sectionsplit
          map_attribute "index", to: :index
          map_attribute "url", to: :url
          map_attribute "fileref", to: :file
          map_element "identifier", to: :identifier
          map_element "type", to: :type
          map_element "title", to: :title
          map_element "bibdata", using: { from: :bibdata_from_xml,
                                          to: :bibdata_to_xml }
          map_element "entry", to: :entry # using: { from: :entry_from_xml, to: :entry_to_xml }
        end

        def entry_from_xml(model, node)
          model.entry = Manifest.from_xml(node.content)
        end

        def entry_to_xml(model, parent, doc)
          Array(model.entry).each do |e|
            elem = e.to_xml
            doc.add_element(parent, elem)
          end
        end

        def level_from_yaml(model, value)
          model.type ||= value
        end

        def fileref_from_yaml(model, value)
          model.file ||= value
        end

        def docref_from_yaml(model, value)
          model.entry = Manifest.from_yaml(value.to_yaml)
        end

        include Converters
      end
    end
  end
end
