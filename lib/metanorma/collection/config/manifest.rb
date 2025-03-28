require "lutaml/model"
require "lutaml/model/xml_adapter/nokogiri_adapter"
require_relative "../../array_monkeypatch"
require_relative "converters"
require_relative "bibdata"

module Metanorma
  class Collection
    module Config
      Lutaml::Model::Config.configure do |config|
        config.xml_adapter = Lutaml::Model::XmlAdapter::NokogiriAdapter
      end

      class Manifest < ::Lutaml::Model::Serializable
        attribute :identifier, :string,
                  default: -> { UUIDTools::UUID.random_create.to_s }
        attribute :id, :string
        attribute :bibdata, Bibdata
        attribute :type, :string
        attribute :title, :string
        attribute :url, :string
        attribute :level, :string
        attribute :attachment, :boolean
        attribute :sectionsplit, :boolean
        attribute :index, :boolean, default: -> { true }
        attribute :entry, Manifest, collection: true
        attribute :file, :string
        attribute :format, :string, collection: true

        yaml do
          map "identifier", to: :identifier
          map "type", to: :type
          map "level", to: :level,
                       with: { from: :level_from_yaml, to: :nop_to_yaml }
          map "title", to: :title
          map "url", to: :url
          map "attachment", to: :attachment
          map "sectionsplit", to: :sectionsplit
          map "index", to: :index
          map "file", to: :file
          map "fileref", to: :file,
                         with: { from: :fileref_from_yaml, to: :nop_to_yaml }
          map "entry", to: :entry
          map "docref", to: :entry,
                        with: { from: :docref_from_yaml, to: :nop_to_yaml }
          map "manifest", to: :entry,
                          with: { from: :docref_from_yaml, to: :nop_to_yaml }
          map "bibdata", to: :bibdata, with: { from: :bibdata_from_yaml,
                                               to: :bibdata_to_yaml }
          map "format", to: :format, render_default: true
        end

        xml do
          root "entry"
          map_attribute "target", to: :id
          map_attribute "attachment", to: :attachment
          map_attribute "sectionsplit", to: :sectionsplit
          map_attribute "index", to: :index
          map_attribute "url", to: :url
          map_attribute "fileref", to: :file
          map_element "identifier", to: :identifier, render_default: true
          map_element "type", to: :type
          map_element "title", to: :title
          map_element "format", to: :format
          map_element "bibdata", to: :bibdata, with: { from: :bibdata_from_xml,
                                                       to: :bibdata_to_xml }
          map_element "entry", to: :entry
        end

        def entry_from_xml(model, node)
          model.entry = Manifest.from_xml(node.node.to_xml)
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
