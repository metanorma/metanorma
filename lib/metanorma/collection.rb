# frozen_string_literal: true

require "relaton"
require "relaton/cli"
require "metanorma/collection_manifest"
require "metanorma-utils"
require_relative "util"

module Metanorma
  # Metanorma collection of documents
  class Collection
    # @return [String]
    attr_reader :file

    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_accessor :directives

    # @return [Hash<String, Metanorma::Document>]
    attr_accessor :documents, :bibdatas, :coverpage

    attr_accessor :disambig, :manifest

    # @param file [String] path to source file
    # @param directives [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    # @param bibdata [RelatonBib::BibliographicItem]
    # @param manifest [Metanorma::CollectionManifest]
    # @param documents [Hash<String, Metanorma::Document>]
    # @param prefatory [String]
    # @param coverpage [String]
    # @param final [String]
    # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    def initialize(**args)
      @file = args[:file]
      @directives = args[:directives] || []
      @bibdata = args[:bibdata]
      @manifest = args[:manifest]
      @manifest.collection = self
      c = @directives.detect { |x| x.is_a?(Hash) && x["coverpage"] }
      c and @coverpage = c["coverpage"]
      c = @directives.detect { |x| x.is_a?(Hash) && x["coverpage-style"] }
      c and @coverpage_style = c["coverpage-style"]
      @documents = args[:documents] || {}
      @bibdatas = args[:documents] || {}
      if @documents.any? && !@directives.include?("documents-inline")
        @directives << "documents-inline"
      end
      @documents.merge! @manifest.documents(File.dirname(@file))
      @bibdatas.merge! @manifest.documents(File.dirname(@file))
      @prefatory = args[:prefatory]
      @final = args[:final]
      @log = Metanorma::Utils::Log.new
      @disambig = Util::DisambigFiles.new
    end

    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength
    def clean_exit
      @log.write(File.join(File.dirname(@file),
                           "#{File.basename(@file, '.*')}.err"))
    end

    # @return [String] XML
    def to_xml
      b = Nokogiri::XML::Builder.new do |xml|
        xml.send(:"metanorma-collection",
                 "xmlns" => "http://metanorma.org") do |mc|
          collection_body(mc)
        end
      end
      b.to_xml
    end

    def collection_body(coll)
      coll << @bibdata.to_xml(bibdata: true, date_format: :full)
      @directives.each do |d|
        coll << "<directives>#{obj_to_xml(d)}</directives>"
      end
      @manifest.to_xml coll
      content_to_xml "prefatory", coll
      doccontainer coll
      content_to_xml "final", coll
    end

    def obj_to_xml(elem)
      case elem
      when ::Array
        elem.each_with_object([]) do |v, m|
          m << "<value>#{obj_to_xml(v)}</value>"
        end.join
      when ::Hash
        elem.each_with_object([]) do |(k, v), m|
          m << "<#{k}>#{obj_to_xml(v)}</#{k}>"
        end.join
      else elem
      end
    end

    def render(opts)
      CollectionRenderer.render self, opts.merge(log: @log)
      clean_exit
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
        xml = Nokogiri::XML File.read(file, encoding: "UTF-8") { |c| c.huge }
        (b = xml.at("/xmlns:metanorma-collection/xmlns:bibdata")) and
          bd = Relaton::Cli.parse_xml(b)
        mnf_xml = xml.at("/xmlns:metanorma-collection/xmlns:manifest")
        mnf = CollectionManifest.from_xml mnf_xml
        pref = pref_final_content xml.at("//xmlns:prefatory-content")
        fnl = pref_final_content xml.at("//xmlns:final-content")
        cov = pref_final_content xml.at("//xmlns:coverpage")
        new(file: file, bibdata: bd, manifest: mnf,
            directives: directives_from_xml(xml.xpath("//xmlns:directives")),
            documents: docs_from_xml(xml, mnf),
            bibdatas: docs_from_xml(xml, mnf),
            prefatory: pref, final: fnl, coverpage: cov)
      end

      # TODO refine
      def directives_from_xml(dir)
        dir.each_with_object([]) do |d, m|
          if d.at("./xmlns:value")
            m << x.xpath("./xmlns:value").map(&:text)
          elsif d.at("./*")
            out = d.elements.each_with_object({}) do |e, ret|
              ret[e.name] = e.children.to_xml
            end
            m << out
          else m << d.children.to_xml
          end
        end
      end

      def parse_yaml(file)
        yaml = YAML.load_file file
        if yaml["bibdata"]
          bd = Relaton::Cli::YAMLConvertor.convert_single_file yaml["bibdata"]
        end
        mnf = CollectionManifest.from_yaml yaml["manifest"]
        dirs = yaml["directives"]
        pref = yaml["prefatory-content"]
        fnl = yaml["final-content"]
        new(file: file, directives: dirs, bibdata: bd, manifest: mnf,
            prefatory: pref, final: fnl)
      end

      # @param xml [Nokogiri::XML::Document]
      # @parma mnf [Metanorma::CollectionManifest]
      # @return [Hash{String=>Metanorma::Document}]
      def docs_from_xml(xml, mnf)
        xml.xpath("//xmlns:doc-container//xmlns:bibdata")
          .each_with_object({}) do |b, m|
          bd = Relaton::Cli.parse_xml b
          docref = mnf.docref_by_id bd.docidentifier.first.id
          m[docref["identifier"]] = Document.new bd, docref["fileref"]
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
      out = sections(dummy_header + cnt.strip)
      builder.send("#{elm}-content") { |b| b << out }
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def sections(cnt)
      c = Asciidoctor.convert(cnt, backend: doctype.to_sym, header_footer: true)
      Nokogiri::XML(c).at("//xmlns:sections").children.to_xml
    end

    # @param builder [Nokogiri::XML::Builder]
    def doccontainer(builder)
      return unless Array(@directives).include? "documents-inline"

      documents.each_with_index do |(_, d), i|
        doccontainer1(builder, d, i)
      end
    end

    def doccontainer1(builder, doc, idx)
      id = format("doc%<index>09d", index: idx)
      builder.send(:"doc-container", id: id) do |b|
        if doc.attachment
          doc.bibitem and b << doc.bibitem.root.to_xml
          b.attachment Metanorma::Utils::datauri(doc.file)
        else doc.to_xml b
        end
      end
    end

    # @return [String]
    def doctype
      @doctype ||= fetch_doctype || "standoc"
    end

    # @return [String]
    def fetch_doctype
      docid = @bibdata.docidentifier.first
      return unless docid

      docid.type&.downcase || docid.id&.sub(/\s.*$/, "")&.downcase
    end
  end
end
