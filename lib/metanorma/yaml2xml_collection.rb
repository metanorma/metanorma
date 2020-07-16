require "relaton-cli"
# require "yaml"
# require "tempfile"
# require "relaton"
# require "metanorma-cli"
# require "nokogiri"

module Metanorma
  class Yaml2XmlColection
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
      <<~END
        <metanorma-collection xmlns="http://metanorma.org">
          #{collection_bibdata}
          #{manifest(@collection["manifest"])}
          #{prefatory}
          #{doccontainer}
          #{final}
        </metanorma-collection>
      END
    end

    private

    # @return [String] bibdata XML
    def collection_bibdata
      return unless @collection["bibdata"] 

      Tempfile.open(["bibdata", ".yml"], encoding: "utf-8") do |f|
        f.write(YAML.dump(@collection["bibdata"])) 
        f.close
        ::Relaton::Cli::YAMLConvertor.new(f).to_xml
        File.read(f.path.sub(/\.yml$/, ".rxl"), encoding: "utf-8")
      end
    end

    # @param mnf [Hash]
    # @return [String] manifest XML element
    def manifest(mnf)
      ret = "<manifest>\n"
      ret += "<level>#{mnf['level']}</level>\n" if mnf["level"]
      ret += "<title>#{mnf['title']}</title>\n" if mnf["title"]
      if mnf["docref"].is_a? Hash
        ret += docref(mnf["docref"])
      elsif mnf["docref"].is_a? Array
        Array(mnf["docref"]).each { |d| ret += docref(d) }
      end
      if mnf["manifest"].is_a? Hash
        ret += manifest(mnf["manifest"])
      elsif mnf["manifest"].is_a? Array
        mnf["manifest"].each { |m| ret += manifest(m) }
      end
      ret += "</manifest>\n"
      ret
    end

    # @param drf [Hash]
    # @return [String] docref XML element
    def docref(drf)
      @docs << { identifier: drf["identifier"], fileref: drf["fileref"], id: "doc%09d" % @docs.size }
      ret = "<docref"
      if Array(@collection["directives"]).include?("documents-inline")
        ret += %( id="#{drf['id']}")
      else
        ret += %( fileref="#{drf['fileref']}")
      end
      ret += ">"
      ret += "<identifier>#{drf['identifier']}</identifier>"
      ret += "</docref>\n"
      ret
    end

    # @return [String]
    def dummy_header
      <<~END
    = X
    A

      END
    end

    # @return [String, nil] XML element
    def prefatory
      return unless @collection["prefatory-content"]

      c =  Asciidoctor.convert(dummy_header + @collection["prefatory-content"], backend: doctype.to_sym, header_footer: true)
      out = Nokogiri::XML(c).at("//xmlns:sections").children.to_xml
      "<prefatory-content>\n#{out}</prefatory-content>"
    end

    # @return [String, nil] XML element
    def final
      return unless @collection["final-content"]

      c =  Asciidoctor.convert(dummy_header + @collection["final-content"], backend: doctype.to_sym, header_footer: true)
      out = Nokogiri::XML(c).at("//xmlns:sections").children.to_xml
      "<final-content>\n#{out}</final-content>"
    end

    # @return [String, nil] XML element
    def doccontainer
      ret = ""
      return unless Array(@collection["directives"]).include?("documents-inline")

      @docs.each do |d|
        ret += "<doc-container id=#{d[:id]}>\n"
        ret += File.read(d[:fileref], encoding: "utf-8")
        ret += "</doc-container>\n\n\n"
      end
      ret
    end

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