# frozen_string_literal: true

require "relaton-cli"

module Metanorma
  # YAML to XML collection converter
  class Yaml2XmlCollection
    # @param file [String] YAML collection file path
    def initialize(file)
      @collection = YAML.load_file(file)
      @docs = []
      require "metanorma-#{doctype}"
    end

    # @param file [String] filename of YAML collection
    # return [String] XML collection
    def self.convert(file)
      new(file).output
    end

    # @return [String] XML collection
    def output
      Nokogiri::XML::Builder.new do |xml|
        xml.send "metanorma-collection", "xmlns" => "http://metanorma.org" do |mc|
          collection_bibdata mc
          manifest(@collection["manifest"], mc)
          prefatory mc
          final mc
        end
      end.to_xml
    end

    private

    # @param builder [Nokogiri::XML::Builder]
    def collection_bibdata(builder)
      return unless @collection["bibdata"] 

      Tempfile.open(["bibdata", ".yml"], encoding: "utf-8") do |f|
        f.write(YAML.dump(@collection["bibdata"])) 
        f.close
        ::Relaton::Cli::YAMLConvertor.new(f).to_xml
        xml = File.read(f.path.sub(/\.yml$/, ".rxl"), encoding: "utf-8")
        builder << xml
      end
    end

    # @param mnf [Hash] manifest
    # @param builder [Nokogiri::XML::Builder]
    def manifest(mnf, builder)
      builder.manifest do |m|
        m.level mnf["level"] if mnf["level"]
        m.title mnf["title"] if mnf["title"]
        manifest_recursion mnf, "docref", m
        manifest_recursion mnf, "manifest", m
      end
    end

    # @param mnf [Hash, Array] manifest
    # @param argname [String]
    # @param builder [Nokogiri::XML::Builder]
    def manifest_recursion(mnf, argname, builder)
      if mnf[argname].is_a?(Hash) then send(argname, mnf[argname], builder)
      elsif mnf[argname].is_a?(Array)
        mnf[argname].map { |m| send(argname, m, builder) }
      end
    end

    # @param drf [Hash] document reference
    # @param builder [Nokogiri::XML::Builder]
    def docref(drf, builder)
      @docs << { identifier: drf["identifier"], fileref: drf["fileref"], id: "doc%09d" % @docs.size }
      dr = builder.docref { |d| d.identifier drf["identifier"] }
      if Array(@collection["directives"]).include?("documents-inline")
        dr[:id] = drf["id"]
      else
        dr[:fileref] = drf["fileref"]
      end
    end

    # @return [String]
    def dummy_header
      <<~DUMMY
        = X
        A

      DUMMY
    end

    # @param builder [Nokogiri::XML::Builder]
    def prefatory(builder)
      content "prefatory-content", builder
    end

    # @param builder [Nokogiri::XML::Builder]
    def final(builder)
      content "final-content", builder
    end

    # @param elm [String] element name
    # @param builder [Nokogiri::XML::Builder]
    def content(elm, builder)
      return unless @collection[elm]

      c = Asciidoctor.convert(dummy_header + @collection[elm],
                              backend: doctype.to_sym, header_footer: true)
      out = Nokogiri::XML(c).at("//xmlns:sections").children.to_xml
      builder.send(elm) { |b| b << out }
    end

    # @return [String, nil] XML element
    # def doccontainer
    #   ret = ""
    #   return unless Array(@collection["directives"]).include?("documents-inline")

    #   @docs.each do |d|
    #     ret += "<doc-container id=#{d[:id]}>\n"
    #     ret += File.read(d[:fileref], encoding: "utf-8")
    #     ret += "</doc-container>\n\n\n"
    #   end
    #   ret
    # end

    # @return [String]
    def doctype
      @doctype ||= if (docid = @collection["bibdata"]["docid"]["type"])
                     docid.downcase
                   elsif (docid = @collection["bibdata"]["docid"])
                     docid.sub(/\s.*$/, "").lowercase
                   else "standoc"
                   end
    end
  end
end
