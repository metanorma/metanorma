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

  # One or more collection members failed to render (#586)
  class RenderFailureException < StandardError; end

  # Metanorma collection of documents
  class Collection
    attr_reader :file, :prefatory, :final

    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_accessor :directives, :documents, :bibdatas, :coverpage,
                  :coverpage_pdf_portfolio, :dirname,
                  :disambig, :manifest, :bibdata, :compile, :config

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
      @directives = (config.directive || []).dup # feeds initialize_directives
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
      @coverpage_pdf_portfolio = d["coverpage-pdf-portfolio"]
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
             manifest: @manifest.config, documents: doc_containers,
             prefatory_content: @prefatory, final_content: @final)
      c.collection = self
      c.to_xml
    end

    # Populate the Config#documents collection with DocContainer wrappers.
    # Only emit them when the `documents-inline` directive is set; otherwise
    # the manifest's <entry fileref=…> already references them externally.
    def doc_containers
      @directives.detect { |d| d.key == "documents-inline" } or return []
      @documents.each_with_index.map do |(_, d), idx|
        ::Metanorma::Collection::Config::DocContainer.new(
          id: format("doc%<index>09d", index: idx),
          content: doccontainer1_inner(d),
        )
      end
    end

    # Inner XML of a single <doc-container> as a string. The body is either
    # the document's <metanorma> presentation root (with its own xmlns) or
    # an attachment payload.
    def doccontainer1_inner(doc)
      b = Nokogiri::XML::Builder.new do |xml|
        xml.send(:wrapper) do |w|
          if doc.attachment
            doc.bibitem and w << doc.bibitem.root.to_xml
            w.attachment Vectory::Utils::datauri(doc.file)
          else
            doc.to_xml w
            w.parent.children.first["flavor"] = Util::taste2flavor(flavor)
          end
        end
      end
      b.parent.elements.first.children.map(&:to_xml).join
    end

    def render(opts)
      opts[:format].nil? || opts[:format].empty? and
        opts[:format] = @format || [:html]
      opts[:log] = @log
      opts[:flavor] = @flavor
      output_folder(opts)
      cr = ::Metanorma::Collection::Renderer.render self, opts
      clean_exit
      render_failures_abort(cr)
      cr
    end

    # A member whose rendering fails no longer lets the collection
    # report success with the document missing from the output (#586).
    # Every member is rendered before aborting, so one run reports all
    # failures; the raise makes callers (CLI, suma) exit non-zero. Runs
    # after clean_exit so the failures are in the written log.
    def render_failures_abort(renderer)
      f = renderer.fatal_errors
      f.empty? and return
      raise RenderFailureException.new(
        "Collection render failed for #{f.size} document(s):\n" +
        f.join("\n"),
      )
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
      @compile.load_flavor(Util::taste2flavor(flavor))
      out = prefatory_parse(
        Util::asciidoc_dummy_header(
          docidentifier: dummy_header_docidentifier,
        ) + cnt.strip,
      )
      builder.send("#{elm}-content") { |b| b << out }
    end

    # Pick a real docidentifier value for the prefatory dummy header so
    # the flavor's metadata_id has something pubid-parseable to put into
    # the bibdata, instead of falling back to its (Liquid-templated)
    # docid_template (issue #558). Prefer the first manifest document's
    # docidentifier (concrete, e.g. "IHO S-97"); fall back to the
    # collection's own (which may carry suffixes like "(all parts)" that
    # pubid won't parse). Both candidates are wrapped because the
    # bibitem field may be a parsed Relaton BibliographicItem in some
    # phases and a Nokogiri::XML::Document in others.
    def dummy_header_docidentifier
      first_doc_docid || @bibdata&.docidentifier&.first&.content
    end

    def first_doc_docid
      bib = documents.values.first&.bibitem or return nil
      if bib.respond_to?(:docidentifier)
        bib.docidentifier&.first&.content
      elsif bib.respond_to?(:at) # Nokogiri (rendering-phase shape)
        # Use local-name() so the match works regardless of whether the
        # rendering-phase document carries a default namespace, without
        # tripping Nokogiri's "undefined namespace prefix" error when
        # it doesn't.
        bib.at("//*[local-name()='docidentifier']")&.text
      end
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def prefatory_parse(cnt)
      x = prefatory_parse_semantic(cnt)
      _, filepath = Util::nokogiri_to_temp(x, "foo", ".presentation.xml")
      c1 = Util::isodoc_create(Util::taste2flavor(@flavor), @manifest.lang,
                               @manifest.script, x,
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
      c = Asciidoctor.convert(cnt, backend: Util::taste2flavor(flavor).to_sym,
                                   header_footer: true)
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

    def flavor
      @flavor ||= fetch_flavor || "standoc"
    end

    # TODO: retrieve flavor based on @bibdata publisher when lookup implemented
    # Will still infer based on docid, but will validate it before proceeding
    def fetch_flavor
      docid = @bibdata&.docidentifier&.first or return
      f = docid.type&.downcase || docid.content&.sub(/\s.*$/,
                                                     "")&.downcase or return
      f = Util::taste2flavor(f)
      require ::Metanorma::Compile.new.stdtype2flavor_gem(f)
      f
    rescue LoadError, NameError
      nil
    end
  end
end
