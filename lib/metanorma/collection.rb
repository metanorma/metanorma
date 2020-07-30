# frozen_string_literal: true

require 'relaton'
require 'relaton/cli'
require 'metanorma/collection_manifest'

module Metanorma
  # Metanorma collection of documents
  class Collection
    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_reader :directives

    # @return [Hash<String, Metanorma::Document>]
    attr_reader :documents

    # @param file [String] path to source file
    # @param directives [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    # @param bibdata [RelatonBib::BibliographicItem]
    # @param manifest [Metanorma::CollectionManifest]
    # @param documents [Hash<String, Metanorma::Document>]
    # @param prefatory [String]
    # @param final [String]
    def initialize(**args) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      @file = args[:file]
      @directives = args[:directives] || []
      @bibdata = args[:bibdata]
      @manifest = args[:manifest]
      @manifest.collection = self
      @documents = args[:documents] || {}
      if @documents.any? && !@directives.include?('documents-inline')
        @directives << 'documents-inline'
      end
      @documents.merge! @manifest.documents(File.dirname(@file))
      @prefatory = args[:prefatory]
      @final = args[:final]
    end

    # @return [String] XML
    def to_xml
      Nokogiri::XML::Builder.new do |xml|
        xml.send('metanorma-collection',
                 'xmlns' => 'http://metanorma.org') do |mc|
          @bibdata.to_xml mc, bibdata: true, date_format: :full
          @manifest.to_xml mc
          content_to_xml 'prefatory', mc
          doccontainer mc
          content_to_xml 'final', mc
        end
      end.to_xml
    end

    class << self
      # @param file [String]
      # @return [RelatonBib::BibliographicItem,
      #   RelatonIso::IsoBibliographicItem]
      def parse(file)
        case file
        when /\.xml$/ then parse_xml(file)
        when /.ya?ml$/ then parse_yaml(file)
        end
      end

      private

      def parse_xml(file)
        xml = Nokogiri::XML File.read(file, encoding: 'UTF-8')
        if (b = xml.at('/xmlns:metanorma-collection/xmlns:bibdata'))
          bd = Relaton::Cli.parse_xml b
        end
        mnf_xml = xml.at('/xmlns:metanorma-collection/xmlns:manifest')
        mnf = CollectionManifest.from_xml mnf_xml
        pref = pref_final_content xml.at('//xmlns:prefatory-content')
        fnl = pref_final_content xml.at('//xmlns:final-content')
        new(file: file, bibdata: bd, manifest: mnf,
            documents: docs_from_xml(xml, mnf), prefatory: pref, final: fnl)
      end

      def parse_yaml(file)
        yaml = YAML.load_file file
        if yaml['bibdata']
          bd = Relaton::Cli::YAMLConvertor.convert_single_file yaml['bibdata']
        end
        mnf = CollectionManifest.from_yaml yaml['manifest']
        dirs = yaml['directives']
        pref = yaml['prefatory-content']
        fnl = yaml['final-content']
        new(file: file, directives: dirs, bibdata: bd, manifest: mnf,
            prefatory: pref, final: fnl)
      end

      # @param xml [Nokogiri::XML::Document]
      # @parma mnf [Metanorma::CollectionManifest]
      # @return [Hash{String=>Metanorma::Document}]
      def docs_from_xml(xml, mnf) # rubocop:disable Metrics/AbcSize
        drfs = mnf.docrefs
        xml.xpath('//xmlns:doc-container/*/xmlns:bibdata').reduce({}) do |m, b|
          bd = Relaton::Cli.parse_xml b
          did = drfs.detect { |k| k == bd.docidentifier.first.id }
          did ||= drfs.detect { |k| %r{^#{k}} =~ bd.docidentifier.first.id }
          m[did] = Document.new bd
          m
        end
      end

      # @param xml [Nokogiri::XML::Element, nil]
      # @return [String, nil]
      def pref_final_content(xml)
        return unless xml

        <<~CONT

          == #{xml.at('title')&.text}
          #{xml.at('p')&.text}
        CONT
      end
    end

    private

    # @return [String, nil]
    attr_reader :prefatory, :final

    # @return [String]
    def dummy_header
      <<~DUMMY
        = X
        A

      DUMMY
    end

    # @param elm [String] 'prefatory' or 'final'
    # @param builder [Nokogiri::XML::Builder]
    def content_to_xml(elm, builder)
      return unless (cnt = send(elm))

      require "metanorma-#{doctype}"
      out = sections(dummy_header + cnt)
      builder.send(elm + '-content') { |b| b << out }
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def sections(cnt)
      c = Asciidoctor.convert(cnt, backend: doctype.to_sym, header_footer: true)
      Nokogiri::XML(c).at('//xmlns:sections').children.to_xml
    end

    # @param builder [Nokogiri::XML::Builder]
    def doccontainer(builder)
      return unless Array(@directives).include? 'documents-inline'

      documents.each_with_index do |(_, d), i|
        id = format('doc%<index>09d', index: i)
        builder.send('doc-container', id: id) { |b| d.to_xml b } # f, id: d[:id]
      end
    end

    # @return [String]
    def doctype
      @doctype ||= fetch_doctype || 'standoc'
    end

    # @return [String]
    def fetch_doctype
      docid = @bibdata.docidentifier.first
      return unless docid

      docid.type&.downcase || docid.id&.sub(/\s.*$/, '')&.downcase
    end
  end
end
