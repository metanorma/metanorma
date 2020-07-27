# frozen_string_literal: true

require 'relaton'
require 'relaton-cli'

module Metanorma
  class Collection
    # @param documents [Hash<String, Metanorma::Document>]
    # @param directives [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    # @param bibdata [RelatonBib::BibliographicItem, nil]
    # @param manifest [Hash]
    # @param prefatory [String]
    # @param final [String]
    def initialize(**args)
      @documents = args[:documents] || {}
      @directives = args[:directives] || []
      @bibdata = args[:bibdata]
      @manifest = args[:manifest] || {}
      @prefatory = args[:prefatory]
      @final = args[:final]
    end

    # @param doc [Metanorma::Document]
    # @return [self]
    # def <<(doc)
    #   docid = doc.identifier.first.id
    #   @documents[docid] = doc
    #   self
    # end

    # @return [String] XML
    def to_xml
      Nokogiri::XML::Builder.new do |xml|
        xml.send('metanorma-collection',
                 'xmlns' => 'http://metanorma.org') do |mc|
          @bibdata.to_xml mc, bibdata: true, date_format: :full
          manifest_to_xml(@manifest, mc)
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
        yaml = YAML.load_file file
        if yaml['bibdata']
          bd = Relaton::Cli::YAMLConvertor.convert_single_file yaml['bibdata']
        end
        mnf = yaml['manifest'] || []
        new(documents: documents(mnf), directives: yaml['directives'],
            bibdata: bd, manifest: mnf, final: yaml['final-content'],
            prefatory: yaml['prefatory-content'])
      end

      private

      # @param mnf [Hash]
      # @return [Hash<String, Metanorma::Document>]
      def documents(mnf, mem = {})
        RelatonBib::HashConverter.array(mnf).reduce(mem) do |mm, m|
          if m['docref']
            RelatonBib::HashConverter.array(m['docref']).each do |dr|
              mm[dr['identifier']] = Document.new(dr['fileref'])
            end
          end
          m['manifest'] ? mem.merge(documents(m['manifest'], mm)) : mm
        end
      end
    end

    private

    # @return [String, nil]
    attr_reader :prefatory, :final

    # @param builder [Nokogiri::XML::Builder]
    def collection_bibdata(builder)
      @documents.each { |doc| doc.to_xml(builder) }
    end

    # @param mnf [Hash] manifest
    # @param builder [Nokogiri::XML::Builder]
    def manifest_to_xml(mnf, builder)
      builder.manifest do |m|
        m.level mnf['level'] if mnf['level']
        m.title mnf['title'] if mnf['title']
        manifest_recursion mnf, 'docref', m
        manifest_recursion mnf, 'manifest', m
      end
    end

    # @param mnf [Hash, Array] manifest
    # @param argname [String]
    # @param builder [Nokogiri::XML::Builder]
    def manifest_recursion(mnf, argname, builder)
      if mnf[argname].is_a?(Hash)
        send(argname + '_to_xml', mnf[argname], builder)
      elsif mnf[argname].is_a?(Array)
        mnf[argname].map { |m| send(argname + '_to_xml', m, builder) }
      end
    end

    # @param drf [Hash] document reference
    # @param builder [Nokogiri::XML::Builder]
    def docref_to_xml(drf, builder)
      # @docs << { identifier: drf['identifier'], fileref: drf['fileref'],
      #            id: 'doc%<size>09d' % { size: @docs.size } }
      dr = builder.docref { |d| d.identifier drf['identifier'] }
      if @directives.include?('documents-inline')
        id = @documents.find_index { |k, _| k == dr['identifier'] } # drf['id']
        dr[:id] = 'doc%<index>09d' % { index: id }
      else
        dr[:fileref] = drf['fileref']
      end
    end

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
      c = Asciidoctor.convert(dummy_header + cnt,
                              backend: doctype.to_sym, header_footer: true)
      out = Nokogiri::XML(c).at('//xmlns:sections').children.to_xml
      builder.send(elm + '-content') { |b| b << out }
    end

    # @param builder [Nokogiri::XML::Builder]
    def doccontainer(builder)
      return unless Array(@directives).include? 'documents-inline'

      @documents.each_with_index do |(_, d), i|
        id = 'doc%<index>09d' % { index: i }
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
