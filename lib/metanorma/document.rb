module Metanorma
  class Document
    # @return [Strin]
    attr_reader :file, :attachment

    # @param bibitem [RelatonBib::BibliographicItem]
    def initialize(bibitem, file, options = {})
      @bibitem = bibitem
      @file = file
      @attachment = options[:attachment]
      @raw = options[:raw]
    end

    class << self
      # @param file [String] file path
      # @param attachment [Bool] is an attachment
      # @return [Metanorma::Document]
      def parse_file(file, attachment)
        new bibitem(file), file, { attachment: attachment }
      end

      # #param xml [Nokogiri::XML::Document, Nokogiri::XML::Element]
      # @return [Metanorma::Document]
      def parse_xml(xml)
        new from_xml(xml)
      end

      # raw XML file, can be used to put in entire file instead of just bibitem
      def raw_file(filename)
        doc = Nokogiri::XML(File.read(filename, encoding: "UTF-8"))
        new(doc, filename, raw: true)
      end

      private

      # #param xml [Nokogiri::XML::Document, Nokogiri::XML::Element]
      # @return [RelatonBib::BibliographicItem,RelatonIso::IsoBibliographicItem]
      def from_xml(xml)
        Relaton::Cli.parse_xml xml.at("//xmlns:bibitem|//xmlns:bibdata")
      end

      # @param file [String]
      # @return [Symbol] file type
      def format(file)
        case file
        when /\.xml$/ then :xml
        when /.ya?ml$/ then :yaml
        end
      end

      # @param file [String]
      # @return [RelatonBib::BibliographicItem,
      #   RelatonIso::IsoBibliographicItem]
      def bibitem(file)
        case format(file)
        when :xml
          from_xml Nokogiri::XML(File.read(file, encoding: "UTF-8"))
        when :yaml
          yaml = File.read(file, encoding: "UTF-8")
          Relaton::Cli::YAMLConvertor.convert_single_file(yaml)
        end
      end
    end

    # @param builder [Nokogiri::XML::Builder, nil]
    # @return [Nokogiri::XML::Builder, String]
    def to_xml(builder = nil)
      if builder
        render_xml builder
      else
        Nokogiri::XML::Builder.new do |b|
          root = render_xml b
          root["xmlns"] = "http://metanorma.org"
        end.to_xml
      end
    end

    # @return [String]
    def type
      @type ||= (@bibitem.docidentifier.first&.type&.downcase ||
                 @bibitem.docidentifier.first&.id&.match(/^[^\s]+/)&.to_s)&.downcase ||
      "standoc"
    end

    private

    def render_xml(builder)
      if @raw
        builder << @bibitem.root.to_xml
      else
        builder.send(type + "-standard") { |b| b << @bibitem.to_xml(bibdata: true) }
      end
    end
  end
end
