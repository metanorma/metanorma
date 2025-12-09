require "relaton-cli"
require "metanorma-utils"
require_relative "util/util"
require_relative "util/disambig_files"
require_relative "config/config"
require_relative "config/manifest"
require_relative "helpers"

module Metanorma
  class FileNotFoundException < StandardError; end

  class AdocFileNotFoundException < StandardError; end

  # Metanorma collection of documents
  class Collection
    attr_reader :file, :prefatory, :final

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
      @log.suppress_log = { severity: 4, category: [], error_ids: [],
                            locations: [] }
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
      tastes = Metanorma::TasteRegister.instance.aliases
      ::Metanorma::Compile.new.load_flavor(tastes[flavor.to_sym] || flavor)
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

    # @param elm [String] 'prefatory' or 'final'
    # @param builder [Nokogiri::XML::Builder]
    def content_to_xml(elm, builder)
      (cnt = send(elm)) or return
      @compile.load_flavor(flavor)
      out = prefatory_parse(Util::asciidoc_dummy_header + cnt.strip)
      builder.send("#{elm}-content") { |b| b << out }
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def prefatory_parse(cnt)
      x = prefatory_parse_semantic(cnt)
      _, filepath = Util::nokogiri_to_temp(x, "foo", ".presentation.xml")
      c1 = Util::isodoc_create(@flavor, @manifest.lang, @manifest.script, x,
                               presxml: true).convert(filepath, nil, true)
      presxml = Nokogiri::XML(c1)
      prefatory_extract_xml(presxml)
    end

    def prefatory_extract_xml(presxml)
      body = presxml.at("//xmlns:sections")
      body.at("//xmlns:p[@class = 'zzSTDTitle1']")&.remove
      body.text.to_s.strip.empty? and body = presxml.at("//xmlns:preface")
      body.at("//xmlns:clause[@type = 'toc']")&.remove
      body.children.to_xml
    end

    def prefatory_parse_semantic(cnt)
      c = Asciidoctor.convert(cnt, backend: flavor.to_sym, header_footer: true)
      x = Nokogiri::XML(c)
      x.xpath("//xmlns:clause").each { |n| n["unnumbered"] = true }
      b = x.at("//xmlns:bibdata")
      prefatory_parse_fix_bibdata(b)
      b.children = ::Metanorma::Standoc::Cleanup::MergeBibitems
        .new(b.to_xml, @bibdata.to_xml(bibdata: true)).merge.to_noko.children
      x
    end

    # Stop standoc ownerless copyright from breaking Relaton parse of bibdata
    def prefatory_parse_fix_bibdata(bibdata)
      if cop = bibdata.at("//xmlns:copyright")
        cop.at("./xmlns:owner") or
          cop.children.first.previous =
            "<owner><organization><name>SDO</name></organization></owner>"
      end
      bibdata
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
          b.parent.children.first["flavor"] = flavor
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
  end
end
