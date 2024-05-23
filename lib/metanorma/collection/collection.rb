# frozen_string_literal: true

require "relaton"
require "relaton/cli"
require "metanorma-utils"
require_relative "../util/util"
require_relative "../collectionconfig/collectionconfig"

module Metanorma
  class FileNotFoundException < StandardError; end

  class AdocFileNotFoundException < StandardError; end

  # Metanorma collection of documents
  class Collection
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
      @dirname = File.expand_path(File.dirname(@file)) # feeds @manifest
      @documents = args[:documents] || {} # feeds initialize_directives
      @bibdatas = args[:documents] || {}
      initialize_vars
      initialize_config(args[:config])
      initialize_directives
      @documents.merge! @manifest.documents(@dirname)
      @bibdatas.merge! @manifest.documents(@dirname)
      @documents.transform_keys { |k| Util::key(k) }
      @bibdatas.transform_keys { |k| Util::key(k) }
    end

    def initialize_vars
      @compile = Metanorma::Compile.new # feeds @manifest
      @log = Metanorma::Utils::Log.new
      @disambig = Util::DisambigFiles.new
    end

    def initialize_config(config)
      @directives = config.directive || [] # feeds initialize_directives
      @bibdata = config.bibdata
      @prefatory = config.prefatory_content
      @final = config.final_content
      @manifest = CollectionManifest.new(config.manifest, self, @dirname) # feeds initialize_directives
    end

    def initialize_directives
      d = @directives.each_with_object({}) { |x, m| m[x.key] = x.value }
      @coverpage = d["coverpage"]
      @coverpage_style = d["coverpage-style"]
      if (@documents.any? || @manifest) && !d.key?("documents-inline") &&
          !d.key?("documents-external")
        @directives << CollectionConfig::Directive.new(key: "documents-inline")
      end
    end

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

    class << self
      # @param Block [Proc]
      # @note allow user-specific function to run in pre-parse model stage
      def set_pre_parse_model(&block)
        @pre_parse_model_proc = block
      end

      # @param Block [Proc]
      # @note allow user-specific function to resolve identifier
      def set_identifier_resolver(&block)
        @identifier_resolver = block
      end

      # @param Block [Proc]
      # @note allow user-specific function to resolve fileref
      # NOTE: MUST ALWAYS RETURN PATH relative to working directory
      # (initial YAML file location). @fileref_resolver.call(ref_folder, fileref)
      # fileref is not what is in the YAML, but the resolved path
      # relative to the working directory
      def set_fileref_resolver(&block)
        @fileref_resolver = block
      end

      def unset_fileref_resolver
        @fileref_resolver = nil
      end

      # @param collection_model [Hash{String=>String}]
      def pre_parse_model(collection_model)
        @pre_parse_model_proc or return
        @pre_parse_model_proc.call(collection_model)
      end

      # @param identifier [String]
      # @return [String]
      def resolve_identifier(identifier)
        @identifier_resolver or return identifier
        @identifier_resolver.call(identifier)
      end

      # @param fileref [String]
      # @return [String]
      def resolve_fileref(ref_folder, fileref)
        unless @fileref_resolver
          (Pathname.new fileref).absolute? or
            fileref = File.join(ref_folder, fileref)
          return fileref
        end

        @fileref_resolver.call(ref_folder, fileref)
      end

      # @param filepath
      # @raise [FileNotFoundException]
      def check_file_existence(filepath)
        unless File.exist?(filepath)
          error_message = "#{filepath} not found!"
          Util.log("[metanorma] Error: #{error_message}", :error)
          raise FileNotFoundException.new error_message.to_s
        end
      end

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
  end
end
