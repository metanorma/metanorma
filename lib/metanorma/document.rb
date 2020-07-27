module Metanorma
  class Document
    # @param file [String] file path
    # @param format [Symbol] file format
    # @param type [String, nil] document type
    # @param output_format [Araay<Symbol>]
    def initialize(file)
      @file = file
    end

    # @param file [String] file path
    # @return [Metanorma::Document]
    # def self.parse(file)
    #   new file
    # end

    # @param builder [Nokogiri::XML::Builder]
    def to_xml(builder)
      builder.send(type + '-standard') { |b| bibitem.to_xml b }
    end

    private

    # @return [Symbol]
    def format
      @format ||= case @file
                  when /\.xml$/ then :xml
                  when /.ya?ml$/ then :yaml
                  end
    end

    # @return [RelatonBib::BibliographicItem, RelatonIso::IsoBibliographicItem]
    def bibitem
      @bibitem ||= case format
                   when :xml
                     xml = Nokogiri::XML File.read @file, encoding: 'UTF-8'
                     Relaton::Cli.parse_xml xml
                   when :yaml
                     yaml = File.read(@file, ecoding: 'UTF-8')
                     Relaton::Cli::YAMLConvertor.convert_single_file(yaml)
                   end
    end

    # @return [String]
    def type
      @type ||= bibitem.docidentifier.first.type
    end
  end
end
