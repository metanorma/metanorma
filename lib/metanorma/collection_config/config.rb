require "shale"
require_relative "../shale_monkeypatch"
require_relative "../array_monkeypatch"
require_relative "compile_options"
require_relative "converters"
require_relative "bibdata"
require_relative "directive"
require_relative "manifest"

module Metanorma
  module CollectionConfig
    require "shale/adapter/nokogiri"
    ::Shale.xml_adapter = ::Shale::Adapter::Nokogiri

    class Config < ::Shale::Mapper
      attr_accessor :path, :collection, :from_xml

      attribute :bibdata, Bibdata
      attribute :directive, Directive, collection: true
      attribute :manifest, Manifest
      attribute :format, ::Shale::Type::String, collection: true,
                                                default: -> { [:html] }
      attribute :output_folder, ::Shale::Type::String
      attribute :coverpage, ::Shale::Type::String, default: -> { "cover.html" }
      attribute :compile, CompileOptions
      attribute :prefatory_content, ::Shale::Type::String
      attribute :final_content, ::Shale::Type::String
      attribute :documents, Bibdata, collection: true
      attribute :xmlns, ::Shale::Type::String, default: -> { "http://metanorma.org" }

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
        map "prefatory-content", to: :prefatory_content
        map "final-content", to: :final_content
      end

      xml do
        root "metanorma-collection"
        # namespace "http://metanorma.org", "m"
        # map_attribute "xmlns", to: :xmlns
        map_element "bibdata", using: { from: :bibdata_from_xml,
                                        to: :bibdata_to_xml }
        map_element "directive", using: { from: :directive_from_xml,
                                          to: :directive_to_xml }
        map_element "entry", using: { from: :manifest_from_xml,
                                      to: :manifest_to_xml }
        map_element "format", to: :format
        map_element "output_folder", to: :output_folder
        map_element "coverpage", to: :coverpage
        map_element "compile", to: :compile
        map_element "prefatory-content", using: { from: :prefatory_from_xml,
                                                  to: :prefatory_to_xml }
        map_element "doc-container",
                    using: { from: :documents_from_xml, to: :documents_to_xml }
        map_element "final-content", using: { from: :final_from_xml,
                                              to: :final_to_xml }
      end

      def manifest_from_xml(model, node)
        model.manifest = Manifest.from_xml(node.to_xml)
      end

      def manifest_to_xml(model, parent, doc)
        model.collection&.manifest&.clean_manifest(model.manifest)
        doc.add_element(parent, model.manifest.to_xml)
      end

      def prefatory_from_xml(model, node)
        model.prefatory_content = node.to_xml
      end

      def prefatory_to_xml(model, parent, doc)
        content_to_xml(model, parent, doc, "prefatory")
      end

      def final_to_xml(model, parent, doc)
        content_to_xml(model, parent, doc, "final")
      end

      def content_to_xml(model, parent, doc, type)
        x = model.send("#{type}_content") or return
        n = Nokogiri::XML(x)
        elem = if n.elements.size == 1 then n.root
              else
                b = Nokogiri::XML::Builder.new
                model.collection.content_to_xml(type, b)
                b.parent.elements.first
              end
        doc.add_element(parent, elem)
      end

      def final_from_xml(model, node)
        model.final_content = node.to_xml
      end

      def directive_from_xml(model, node)
        model.directive ||= []
        model.directive << Directive.from_xml(node.to_xml)
      end

      def directive_to_xml(model, parent, doc)
        Array(model.directive).each do |e|
          elem = e.to_xml
          doc.add_element(parent, elem)
        end
      end

      def directives_from_yaml(model, value)
        model.directive = value&.each_with_object([]) do |v, m|
          m << case v
              when String then Directive.new(key: v)
              when Hash
                k = v.keys.first
                Directive.new(key: k, value: v[k])
              end
        end
      end

      def directives_to_yaml(model, doc)
        doc["directives"] = model.directive.each_with_object([]) do |d, m|
          m << { d.key => d.value }
        end
      end

      def documents_from_xml(model, value)
        x = if value.is_a?(Shale::Adapter::Nokogiri::Node)
              value.content
            else Nokogiri::XML(value)
            end
        model.documents = x.xpath(".//bibdata")
          .each_with_object([]) do |b, m|
          m << Bibdata.from_xml(b.to_xml)
        end
      end

      def documents_to_xml(model, parent, doc)
        b = Nokogiri::XML::Builder.new do |xml|
          xml.document do |m|
            model.collection.doccontainer(m) or return
          end
        end
        b.parent.elements.first.elements.each do |x|
          doc.add_element(parent, x)
        end
      end

      include Converters
    end
  end
end