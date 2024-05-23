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
    extend CollectionConstructModel

    attr_reader :file

    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_accessor :directives, :documents, :bibdatas, :coverpage, :dirname
    attr_accessor :disambig, :manifest, :bibdata, :compile

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
      config = args[:config]
      @directives = config.directive || []
      @bibdata = config.bibdata
      @dirname = File.expand_path(File.dirname(@file))
      @compile = Metanorma::Compile.new # feeds manifest
      @manifest = CollectionManifest.new(config.manifest, self, @dirname)
      # @coverpage = Util::hash_key_detect(@directives, "coverpage", @coverpage)
      # @coverpage_style = Util::hash_key_detect(@directives, "coverpage-style",
      # @coverpage_style)
      @coverpage = @directives.detect { |d| d.key == "coverpage" }&.value
      @coverpage_style = @directives.detect do |d|
                           d.key == "coverpage-style"
                         end&.value
      @documents = args[:documents] || {}
      @bibdatas = args[:documents] || {}
      directive_keys = @directives.map(&:key)
      if (@documents.any? || @manifest) &&
          (%w(documents-inline documents-external) & directive_keys).empty?
        # @directives << "documents-inline"
        @directives << CollectionConfig::Directive.new(key: "documents-inline")
      end
      @documents.merge! @manifest.documents(@dirname)
      @bibdatas.merge! @manifest.documents(@dirname)
      @documents.transform_keys { |k| Util::key(k) }
      @bibdatas.transform_keys { |k| Util::key(k) }
      @prefatory = config.prefatory_content
      @final = config.final_content
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
      c = CollectionConfig::Config
        .new(directive: @directives, bibdata: @bibdata,
             manifest: @manifest.config, documents: @documents,
             prefatory_content: @prefatory, final_content: @final)
      c.collection = self
      c.to_xml # .sub("<metanorma-collection", "<metanorma-collection xmlns='http://metanorma.org'")
    end

    def render(opts)
      CollectionRenderer.render self, opts.merge(log: @log)
      clean_exit
    end

    class << self
      def parse(file)
        # need @dirname initialised before collection object initialisation
        @dirname = File.expand_path(File.dirname(file))
        config = case file
                 when /\.xml$/
                   CollectionConfig::Config.from_xml(File.read(file))
                 when /.ya?ml$/
                   y = YAML.safe_load(File.read(file))
                   pre_parse_model(y)
                   CollectionConfig::Config.from_yaml(y.to_yaml)
                 end
        new(file: file, config: config)
      end
    end

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
      # Array(@directives).include? "documents-inline" or return
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
        else
          doc.to_xml b
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
