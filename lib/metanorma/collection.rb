# frozen_string_literal: true

require "relaton"
require "relaton/cli"
require "metanorma/collection_manifest"
require "metanorma-utils"
require_relative "util"
require_relative "collection_construct_model"
require_relative "collectionconfig/collectionconfig"

module Metanorma
  class FileNotFoundException < StandardError; end

  class AdocFileNotFoundException < StandardError; end

  # Metanorma collection of documents
  class Collection
    attr_reader :file

    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_accessor :directives, :documents, :bibdatas, :coverpage, :dirname
    attr_accessor :disambig, :manifest

    # @param file [String] path to source file
    # @param dirname [String] directory of source file
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
      @dirname = File.dirname(@file)
      config = args[:config]
      @directives = config.directives || []
      @bibdata = config.bibdata
      @manifest = CollectionManifest.new(config.manifest)
      @manifest.collection = self
      #@coverpage = Util::hash_key_detect(@directives, "coverpage", @coverpage)
      #@coverpage_style = Util::hash_key_detect(@directives, "coverpage-style",
                                               #@coverpage_style)
      @coverpage = @directives.detect { |d| d.key == "coverpage" }&.value
      @coverpage_style = @directives.detect { |d| d.key == "coverpage-style" }&.value
      @documents = args[:documents] || {}
      @bibdatas = args[:documents] || {}
      directive_keys = @directives.map(&:key)
      if (@documents.any? || @manifest) &&
          (%w(documents-inline documents-external) & directive_keys).empty?
        #@directives << "documents-inline"
        @directives << ConfigureCollection::Directive.new(key: "documents-inline")
      end
      @documents.merge! @manifest.documents(@dirname)
      @bibdatas.merge! @manifest.documents(@dirname)
      @documents.transform_keys { |k| Util::key(k) }
      @bibdatas.transform_keys { |k| Util::key(k) }
      @prefatory = config.prefatory_content
      @final = config.final_content
      @compile = Metanorma::Compile.new
      @log = Metanorma::Utils::Log.new
      @disambig = Util::DisambigFiles.new
    end

    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength
    def clean_exit
      @log.write(File.join(@dirname,
                           "#{File.basename(@file, '.*')}.err.html"))
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

    def collection_body(coll) # KILL
      #coll << @bibdata.to_xml(bibdata: true, date_format: :full)
      @directives.each do |d|
        coll << "<directives>#{obj_to_xml(d)}</directives>"
      end
      @manifest.to_xml coll
      content_to_xml "prefatory", coll
      doccontainer coll
      content_to_xml "final", coll
    end

    def collection_body(coll)
      coll << @bibdata.to_xml(bibdata: true, date_format: :full)
      @directives.each { |d| coll << d.to_xml }
      @manifest.to_xml coll
      content_to_xml "prefatory", coll
      doccontainer coll
      content_to_xml "final", coll
    end

    def obj_to_xml(elem) # KILL
      case elem
      when ::Array
        elem.each_with_object([]) do |v, m|
          m << "<value>#{obj_to_xml(v)}</value>"
        end.join
      when ::Hash
        elem.each_with_object([]) do |(k, v), m|
          m << "<#{k}>#{obj_to_xml(v)}</#{k}>"
        end.join
      else elem end
    end

    def render(opts)
      CollectionRenderer.render self, opts.merge(log: @log)
      clean_exit
    end

    class << self
      def parse(file)
        config = case file
                 when /\.xml$/
                   CollectionConfig::Config.from_xml(File.read(file))
                 when /.ya?ml$/
                   CollectionConfig::Config.from_yaml(File.read(file))
                 end
        new(file: file, config: config)
      end

      #def parse(file)
        #case file
        #when /\.xml$/ then parse_xml(file)
        #when /.ya?ml$/ then parse_yaml(file)
        #end
      #end

      private

      def parse_xml(file) # KILL
        xml = Nokogiri::XML(File.read(file, encoding: "UTF-8"), &:huge)
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

        new(file: file, directives: dirs, bibdata: bd, manifest: mnf,
            prefatory: pref, final: fnl)
      end

      # TODO refine
      def directives_from_xml(dir) # KILL
        dir.each_with_object([]) do |d, m|
          m << if d.at("./xmlns:value")
                 x.xpath("./xmlns:value").map(&:text)
               elsif d.at("./*")
                 d.elements.each_with_object({}) do |e, ret|
                   ret[e.name] = e.children.to_xml
                 end
               else d.children.to_xml
               end
        end
      end

      def parse_yaml(file)
        collection_model = YAML.load_file file
        if new_yaml_format?(collection_model)
          collection_model = construct_collection_manifest(collection_model)
          file = File.basename(file)
        end
        pre_parse_model(collection_model)
        if collection_model["manifest"]["manifest"]
          compile_adoc_documents(collection_model)
        end
        parse_model(file, collection_model)
      end

      # @param xml [Nokogiri::XML::Document]
      # @param mnf [Metanorma::CollectionManifest]
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
        xml or return
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
      (cnt = send(elm)) or return
      @compile.load_flavor(doctype)
      out = sections(dummy_header + cnt.strip)
      builder.send("#{elm}-content") { |b| b << out }
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def sections(cnt)
      c = Asciidoctor.convert(cnt, backend: doctype.to_sym, header_footer: true)
      Nokogiri::XML(c, &:huge).at("//xmlns:sections").children.to_xml
    end

    # @param builder [Nokogiri::XML::Builder]
    def doccontainer(builder)
      #Array(@directives).include? "documents-inline" or return
      @directives.detect { |d| d.key == "documents-inline" } or return
      documents.each_with_index do |(_, d), i|
        doccontainer1(builder, d, i)
      end
    end

    def doccontainer1(builder, doc, idx)
      id = format("doc%<index>09d", index: idx)
      builder.send(:"doc-container", id: id) do |b|
        if doc.attachment
          doc.bibitem and b << doc.bibitem.root.to_xml
          b.attachment Vectory::Utils::datauri(doc.file)
        else doc.to_xml b
        end
      end
    end

    def doctype
      @doctype ||= fetch_doctype || "standoc"
    end

    def fetch_doctype
      docid = @bibdata.docidentifier.first
      docid or return
      docid.type&.downcase || docid.id&.sub(/\s.*$/, "")&.downcase
    end
  end
end
