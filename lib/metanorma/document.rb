module Metanorma
  class Document
    # @param bibitem [RelatonBib::BibliographicItem]
    def initialize(bibitem)
      @bibitem = bibitem
    end

    class << self
      # @param file [String] file path
      # @return [Metanorma::Document]
      def parse_file(file)
        new bibitem(file)
      end

      # #param xml [Nokogiri::XML::Document, Nokogiri::XML::Element]
      # @return [Metanorma::Document]
      def parse_xml(xml)
        new from_xml(xml)
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
          yaml = File.read(file, ecoding: "UTF-8")
          Relaton::Cli::YAMLConvertor.convert_single_file(yaml)
        end
      end
    end

    # @param builder [Nokogiri::XML::Builder]
    def to_xml(builder)
      builder.send(type + "-standard") { |b| @bibitem.to_xml b, bibdata: true }
    end

    private

    # @return [String]
    def type
      @type ||= @bibitem.docidentifier.first.type.downcase
    end
  end
end
