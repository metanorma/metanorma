require "fileutils"
require "relaton"
require "relaton-cli"
require "yaml"
require "shale"
require "shale/adapter/nokogiri"

module CollectionConfig
  ::Shale.xml_adapter = ::Shale::Adapter::Nokogiri

  module Converters
    def bibdata_from_yaml(model, value)
      model.bibdata = Relaton::Cli::YAMLConvertor.convert_single_file(value)
    end

    def bibdata_to_yaml(model, doc)
      doc["bibdata"] = model.bibdata.to_yaml
    end

    def bibdata_from_xml(model, node)
      model.bibdata = Relaton::Cli.parse_xml(node.to_xml)
    end

    def bibdata_to_xml(model, parent, doc)
      b = model.bibdata or return
      elem = b.to_xml(bibdata: true)#, date_format: :full)
      doc.add_element(parent, elem)
    end
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
      root "manifest"
      map_attribute "id", to: :id
      map_attribute "attachment", to: :attachment
      map_attribute "sectionsplit", to: :sectionsplit
      map_attribute "index", to: :index
      map_element "identifier", to: :identifier
      map_element "type", to: :type
      map_element "title", to: :title
      map_element "bibdata", using: { from: :bibdata_from_xml,
                                      to: :bibdata_to_xml }
      map_element "url", to: :url
      map_element "file", to: :file
      map_element "entry", to: :entry
    end

    def nop(model, value); end

    def entry_to_yaml(model, doc)
      doc["entry"] = model.entry
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

    #     def attachments
    #       docref.detect do |ref|
    #         ref.type == "attachments"
    #       end&.docref
    #     end
    #
    #     def documents
    #       docref.detect do |ref|
    #         ref.type == "document"
    #       end&.docref
    #     end
    include ::CollectionConfig::Converters
  end

  class Config < ::Shale::Mapper
    attr_accessor :path

    attribute :directives, ::Shale::Type::String, collection: true
    attribute :bibdata, Bibdata
    attribute :manifest, Manifest
    attribute :format, ::Shale::Type::String, collection: true,
                                              default: -> { [:html] }
    attribute :output_folder, ::Shale::Type::String
    attribute :coverpage, ::Shale::Type::String, default: -> { "cover.html" }
    attribute :compile, CompileOptions
    attribute :prefatory_content, ::Shale::Type::String
    attribute :final_content, ::Shale::Type::String
    attribute :documents, Bibdata, collection: true

    yaml do
      map "directives", using: { from: :directives_from_yaml,
                                 to: :directives_to_yaml }
      map "bibdata", using: { from: :bibdata_from_yaml,
                              to: :bibdata_to_yaml }
      map "manifest", to: :manifest
      map "format", to: :format
      map "output_folder", to: :output_folder
      map "coverpage", to: :coverpage
      map "compile", to: :compile
      map "prefatory-content", to: :prefatory_content # TODO Metanorma serialise
      map "final-content", to: :final_content # TODO Metanorma serialise
      map "directive", to: :directive
    end

    xml do
      root "collection"
      map_element "directives", using: { from: :directives_from_xml,
                                         to: :directives_to_xml }
      map_element "bibdata", using: { from: :bibdata_from_xml,
                                      to: :bibdata_to_xml }
      map_element "manifest", to: :manifest
      map_element "format", to: :format
      map_element "output_folder", to: :output_folder
      map_element "coverpage", to: :coverpage
      map_element "compile", to: :compile
      map_element "prefatory-content", to: :prefatory_content # TODO Metanorma serialise
      map_element "final-content", to: :final_content # TODO Metanorma serialise
      map_element "directive", to: :directive
      map_element "doc-container",
                  using: { from: :documents_from_xml, to: :nop }
    end

    def directives_from_yaml(model, value)
      model.directives = value.each_with_object([]) do |v, m|
        m << case v
             when String then Directive.new(key: v)
             when Hash
               k = v.keys.first
               Directive.new(key: k, value: v[k])
             end
      end
    end

    def directives_to_yaml(model, doc)
      doc["directives"] = model.directives.each_with_object([]) do |d, m|
        m << { d.key => d.value }
      end
    end

    def directives_from_xml(model, node)
      model.directives = if node.text?
                           Directive.new(key: node.text)
                         else
                           Directive.new(key: node.name, value: node.text)
                         end
    end

    def directives_to_xml(model, parent, doc)
      model.directives.each do |d|
        if d.value.nil?
          dir = doc.create_element("directives")
          doc.add_text(dir, d.key)
          doc.add_element(parent, dir)
        else
          elem = doc.create_element(d.key)
          doc.add_text(elem, d.value)
          doc.add_element(parent, elem)
        end
      end
    end

    def nop(model, value); end

    def documents_from_xml(model, value)
      x = Nokogiri::XML(value)
      model.documents = x.xpath(".//xmlns::bibdata")
        .each_with_object([]) do |b, m|
        m << Bibdata.from_xml(b.to_xml)
      end
    end

    include ::CollectionConfig::Converters
  end
end
