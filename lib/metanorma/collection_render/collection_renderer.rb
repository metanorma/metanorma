require "isodoc"
require "htmlentities"
require_relative "collection_fileprocess"
require_relative "../util/fontist_helper"
require_relative "../util/util"
require_relative "../collection_files_lookup/files_lookup"
require_relative "collection_render_utils"
require_relative "collection_render_word"
require_relative "collection_navigation"

module Metanorma
  # XML collection renderer
  class CollectionRenderer
    FORMATS = %i[html xml doc pdf].freeze

    attr_accessor :isodoc, :nested
    attr_reader :xml, :compile, :compile_options, :documents, :outdir, :manifest

    # This is only going to render the HTML collection
    # @param xml [Metanorma::Collection] input XML collection
    # @param folder [String] input folder
    # @param options [Hash]
    # @option options [String] :coverpage cover page HTML (Liquid template)
    # @option options [Array<Symbol>] :format list of formats (xml,html,doc,pdf)
    # @option options [String] :output_folder output directory
    #
    # We presuppose that the bibdata of the document is equivalent to that of
    # the collection, and that the flavour gem can sensibly process it. We may
    # need to enhance metadata in the flavour gems isodoc/metadata.rb with
    # collection metadata
    def initialize(collection, folder, options = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      check_options options
      @xml = Nokogiri::XML collection.to_xml # @xml is the collection manifest
      @xml.root.default_namespace = "http://metanorma.org"
      @lang = collection.bibdata.language.first || "en"
      @script = collection.bibdata.script.first || "Latn"
      @locale = @xml.at("//xmlns:bibdata/xmlns:locale")&.text
      @doctype = doctype
      @compile = Compile.new
      @compile.load_flavor(@doctype)

      @isodoc = isodoc_create # output processor for flavour
      @outdir = dir_name_cleanse(options[:output_folder])
      @coverpage = options[:coverpage] || collection.coverpage
      @format = Util.sort_extensions_execution(options[:format])
      @compile_options = options[:compile] || {}
      @compile_options[:no_install_fonts] = true if options[:no_install_fonts]
      @log = options[:log]
      @bibdata = collection.bibdata
      @documents = collection.documents
      @bibdatas = collection.documents
      @directives = collection.directives
      @dirname = collection.dirname
      @manifest = collection.manifest.config
      @disambig = Util::DisambigFiles.new
      @prefatory = collection.prefatory
      @final = collection.final
      @c = HTMLEntities.new
      @files_to_delete = []
      @nested = options[:nested] # if false, this is the root instance of Renderer
      # if true, then this is not the last time Renderer will be run
      # (e.g. this is sectionsplit)

      # list of files in the collection
      @files = Metanorma::FileLookup.new(folder, self)
      @files.add_section_split
      isodoc_populate
      create_non_existing_directory(@outdir)
    end

    def flush_files
      warn "\n\n\n\n\nDone: #{DateTime.now.strftime('%H:%M:%S')}"
      warn @files.files_to_delete
      @files.files_to_delete.each { |f| FileUtils.rm_f(f) }
      @files_to_delete.each { |f| FileUtils.rm_f(f) }
    end

    # @param col [Metanorma::Collection] XML collection
    # @param options [Hash]
    # @option options [String] :coverpage cover page HTML (Liquid template)
    # @option options [Array<Symbol>] :format list of formats
    # @option options [Strong] :ourput_folder output directory
    def self.render(col, options = {})
      warn "\n\n\n\n\nRender Init: #{DateTime.now.strftime('%H:%M:%S')}"
      cr = new(col, File.dirname(col.file), options)
      cr.files
      cr.concatenate(col, options)
      options[:format]&.include?(:html) and cr.coverpage
      cr.flush_files
      cr
    end

    def concatenate(col, options)
      warn "\n\n\n\n\nConcatenate: #{DateTime.now.strftime('%H:%M:%S')}"
      (options[:format] & %i(pdf doc)).empty? or
        options[:format] << :presentation
      concatenate_prep(col, options)
      concatenate_outputs(options)
    end

    def concatenate_prep(col, options)
      %i(xml presentation).each do |e|
        options[:format].include?(e) or next
        ext = e == :presentation ? "presentation.xml" : e.to_s
        File.open(File.join(@outdir, "collection.#{ext}"), "w:UTF-8") do |f|
          b = concatenate1(col.clone, e).to_xml
          e == :presentation and
            b.sub!("<metanorma-collection>", "<metanorma-collection xmlns='http://metanorma.org'>")
          # TODO BEING FORCED TO DO THAT BECAUSE SHALE IS NOT DEALING WITH DEFAULT NAMESPACES
          f.write(b)
        end
      end
    end

    def concatenate_outputs(options)
      pres = File.join(@outdir, "collection.presentation.xml")
      options[:format].include?(:pdf) and pdfconv.convert(pres)
      options[:format].include?(:doc) and docconv_convert(pres)
    end

    def concatenate1(out, ext)
      out.directives << CollectionConfig::Directive.new(key: "documents-inline")
      out.bibdatas.each_key do |ident|
        id = @isodoc.docid_prefix(nil, ident.dup)
        @files.get(id, :attachment) || @files.get(id, :outputs).nil? and next
        out.documents[Util::key id] =
          Metanorma::Document.raw_file(@files.get(id, :outputs)[ext])
      end
      out
    end

    # infer the flavour from the first document identifier; relaton does that
    def doctype
      if (docid = @xml.at("//bibdata/docidentifier/@type")&.text)
        dt = docid.downcase
      elsif (docid = @xml.at("//bibdata/docidentifier")&.text)
        dt = docid.sub(/\s.*$/, "").lowercase
      else return "standoc"
      end
      @registry = Metanorma::Registry.instance
      @registry.alias(dt.to_sym)&.to_s || dt
    end

    # populate liquid template of ARGV[1] with metadata extracted from
    # collection manifest
    def coverpage
      @coverpage or return
      warn "\n\n\n\n\nCoverpage: #{DateTime.now.strftime('%H:%M:%S')}"
      File.open(File.join(@outdir, "index.html"), "w:UTF-8") do |f|
        f.write @isodoc.populate_template(File.read(@coverpage))
      end
    end
  end
end
