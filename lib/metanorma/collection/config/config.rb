require "lutaml/model"
require_relative "../../array_monkeypatch"
require_relative "compile_options"
require_relative "converters"
require_relative "bibdata"
require_relative "directive"
require_relative "manifest"

module Metanorma
  class Collection
    module Config
      Lutaml::Model::Config.configure do |config|
        config.xml_adapter = Lutaml::Model::XmlAdapter::NokogiriAdapter
      end

      class Config < ::Lutaml::Model::Serializable
        attr_accessor :path, :collection, :from_xml

        attribute :bibdata, Bibdata
        attribute :directive, Directive, collection: true
        attribute :manifest, Manifest
        attribute :coverpage, :string, default: -> { "cover.html" }
        attribute :coverpage_pdf_portfolio, :string
        attribute :format, :string, collection: true, default: -> { [:html] }
        attribute :output_folder, :string
        attribute :compile, CompileOptions
        attribute :prefatory_content, :string, raw: true
        attribute :final_content, :string, raw: true
        attribute :documents, Bibdata, collection: true
        attribute :xmlns, :string, default: -> { "http://metanorma.org" }

        yaml do
          map "directives", to: :directive, with: { from: :directives_from_yaml,
                                                    to: :directives_to_yaml }
          map "bibdata", to: :bibdata, with: { from: :bibdata_from_yaml,
                                               to: :bibdata_to_yaml }
          map "manifest", to: :manifest
          map "entry", to: :manifest, with: { from: :entry_from_yaml,
                                              to: :nop_to_yaml }
          map "format", to: :format, render_default: true
          map "output_folder", to: :output_folder
          map "coverpage", to: :coverpage, render_default: true
          map "coverpage-pdf-portfolio", to: :coverpage_pdf_portfolio,
                                         render_default: true
          map "compile", to: :compile, render_default: true
          map "prefatory-content", to: :prefatory_content
          map "final-content", to: :final_content
        end

        xml do
          root "metanorma-collection"
          # namespace "http://metanorma.org", "m"
          # map_attribute "xmlns", to: :xmlns
          map_element "bibdata", to: :bibdata, with: { from: :bibdata_from_xml,
                                                       to: :bibdata_to_xml }
          map_element "directive", to: :directive
          map_element "entry", to: :manifest, with: { from: :manifest_from_xml,
                                                      to: :manifest_to_xml }
          map_element "format", to: :format, render_default: true
          map_element "output_folder", to: :output_folder
          map_element "coverpage", to: :coverpage, render_default: true
          map_element "coverpage-pdf-portfolio", to: :coverpage_pdf_portfolio,
                                                 render_default: true
          map_element "compile", to: :compile, render_default: true
          map_element "prefatory-content",
                      to: :prefatory_content,
                      with: { from: :prefatory_from_xml,
                              to: :prefatory_to_xml }
          map_element "doc-container",
                      to: :documents,
                      with: { from: :documents_from_xml,
                              to: :documents_to_xml }
          map_element "final-content",
                      to: :final_content,
                      with: { from: :final_from_xml,
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
          model.prefatory_content = node.children.map(&:to_xml).join
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
          elem = if n.elements.size == 1
                   "<#{type}-content>#{x}</#{type}-content>" # n.root
                 else
                   b = Nokogiri::XML::Builder.new
                   model.collection.content_to_xml(type, b)
                   b.parent.elements.first
                 end
          doc.add_element(parent, elem)
        end

        def final_from_xml(model, node)
          model.final_content = node.children.map(&:to_xml).join
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

        def entry_from_yaml(model, value)
          model.manifest ||= value
        end

        def self.flavor_from_yaml(yaml)
          yaml["directives"]&.detect do |x|
            x.is_a?(Hash) && x.has_key?("flavor")
          end&.dig("flavor")&.upcase
        end

        def self.flavor_to_bibdata(file)
          # propagate flavor from directives to bibdata
          yaml = YAML.safe_load(file)
          flavor = flavor_from_yaml(yaml) or return file
          yaml["bibdata"] or return file
          yaml["bibdata"]["ext"] ||= {}
          yaml["bibdata"]["ext"]["flavor"] ||= flavor
          yaml.to_yaml
        end

        def self.from_yaml(file)
          file = flavor_to_bibdata(file)
          super
        end

        include Converters
      end
    end
  end
end
