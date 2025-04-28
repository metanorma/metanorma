require "relaton"
require "relaton/cli"
require "metanorma-utils"
require_relative "util/util"
require_relative "util/disambig_files"
require_relative "config/config"
require_relative "config/manifest"

module Metanorma
  class FileNotFoundException < StandardError; end

  class AdocFileNotFoundException < StandardError; end

  # Metanorma collection of documents
  class Collection
    attr_reader :file

    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_accessor :directives, :documents, :bibdatas, :coverpage, :dirname
    attr_accessor :disambig, :manifest, :bibdata, :compile, :config

    # @param file [String] path to source file
    # @param config [Metanorma::Collection::Config]
    # @param documents [Hash<String, Metanorma::Collection::Document>]
    def initialize(**args)
      @file = args[:file]
      @dirname = File.expand_path(File.dirname(@file)) # feeds @manifest
      @documents = args[:documents] || {} # feeds initialize_directives, initialize_docs
      @bibdatas = args[:documents] || {}
      initialize_vars
      initialize_config(args[:config])
      initialize_directives
      initialize_docs
      validate_flavor(flavor)
    end

    def initialize_docs
      @documents.merge! @manifest.documents
      @bibdatas.merge! @manifest.documents
      @documents.transform_keys { |k| Util::key(k) }
      @bibdatas.transform_keys { |k| Util::key(k) }
    end

    def initialize_vars
      @compile = Metanorma::Compile.new # feeds @manifest
      @log = Metanorma::Utils::Log.new
      @disambig = Util::DisambigFiles.new
    end

    def initialize_config(config)
      @config = config
      @directives = config.directive || [] # feeds initialize_directives
      @bibdata = config.bibdata
      @prefatory = config.prefatory_content
      @final = config.final_content
      @manifest = ::Metanorma::Collection::Manifest
        .new(config.manifest, self, @dirname) # feeds initialize_directives
      @format = config.format.map(&:to_sym)
      @format&.empty? and @format = nil
    end

    def initialize_directives
      d = @directives.each_with_object({}) { |x, m| m[x.key] = x.value }
      @coverpage = d["coverpage"]
      @coverpage_style = d["coverpage-style"]
      @flavor = d["flavor"]
      if (@documents.any? || @manifest) && !d.key?("documents-inline") &&
          !d.key?("documents-external")
        @directives << ::Metanorma::Collection::Config::Directive
          .new(key: "documents-inline")
      end
    end

    def validate_flavor(flavor)
      ::Metanorma::Compile.new.load_flavor(flavor)
    end

    def clean_exit
      @log.write(File.join(@dirname,
                           "#{File.basename(@file, '.*')}.err.html"))
    end

    # @return [String] XML
    def to_xml
      c = ::Metanorma::Collection::Config::Config
        .new(directive: @directives, bibdata: @bibdata,
             manifest: @manifest.config, documents: @documents,
             prefatory_content: @prefatory, final_content: @final)
      c.collection = self
      c.to_xml # .sub("<metanorma-collection", "<metanorma-collection xmlns='http://metanorma.org'")
    end

    def render(opts)
      opts[:format].nil? || opts[:format].empty? and
        opts[:format] = @format || [:html]
      opts[:log] = @log
      opts[:flavor] = @flavor
      output_folder(opts)
      ::Metanorma::Collection::Renderer.render self, opts
      clean_exit
    end

    def output_folder(opts)
      opts[:output_folder] ||= config.output_folder
      opts[:output_folder] && !Pathname.new(opts[:output_folder]).absolute? and
        opts[:output_folder] = File.join(@dirname, opts[:output_folder])
      warn opts[:output_folder]
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
      @compile.load_flavor(flavor)
      out = sections(dummy_header + cnt.strip)
      builder.send("#{elm}-content") { |b| b << out }
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def sections(cnt)
      c = Asciidoctor.convert(cnt, backend: flavor.to_sym, header_footer: true)
      x = Nokogiri::XML(c)
      x.xpath("//xmlns:clause").each { |n| n["unnumbered"] = true }
      file = Tempfile.new(%w(foo presentation.xml))
      file.write(x.to_xml(indent: 0))
      file.close
      c1 = Util::isodoc_create(@flavor, @manifest.lang, @manifest.script, x, presxml: true)
        .convert(file.path, nil, true)
      Nokogiri::XML(c1).at("//xmlns:sections").children.to_xml
    end

    # @param builder [Nokogiri::XML::Builder]
    def doccontainer(builder)
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

    def flavor
      @flavor ||= fetch_flavor || "standoc"
    end

    # TODO: retrieve flavor based on @bibdata publisher when lookup implemented
    # Will still infer based on docid, but will validate it before proceeding
    def fetch_flavor
      docid = @bibdata.docidentifier.first or return
      f = docid.type.downcase || docid.id.sub(/\s.*$/, "").downcase or return
      require ::Metanorma::Compile.new.stdtype2flavor_gem(f)
      f
    rescue LoadError
      nil
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
        warn ref_folder
        warn fileref
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
          ::Metanorma::Util.log("[metanorma] Error: #{error_message}", :error)
          raise FileNotFoundException.new error_message.to_s
        end
      end

      def parse(file)
        # need @dirname initialised before collection object initialisation
        @dirname = File.expand_path(File.dirname(file))
        config = case file
                 when /\.xml$/
                   ::Metanorma::Collection::Config::Config.from_xml(File.read(file))
                 when /.ya?ml$/
                   y = YAML.safe_load(File.read(file))
                   pre_parse_model(y)
                   ::Metanorma::Collection::Config::Config.from_yaml(y.to_yaml)
                 end
        new(file: file, config: config)
      end
    end
  end
end
