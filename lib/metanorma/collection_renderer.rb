require "isodoc"
require "htmlentities"
require_relative "collection_fileprocess"
require_relative "fontist_utils"
require_relative "util"
require_relative "files_lookup"
require_relative "collection_render_utils"
require_relative "collection_render_word"

module Metanorma
  # XML collection renderer
  class CollectionRenderer
    FORMATS = %i[html xml doc pdf].freeze

    attr_accessor :isodoc, :nested
    attr_reader :xml, :compile, :compile_options, :documents

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
      @lang = @xml.at("//xmlns:bibdata/xmlns:language")&.text || "en"
      @script = @xml.at("//xmlns:bibdata/xmlns:script")&.text || "Latn"
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
      @documents = collection.documents
      @bibdata = collection.documents
      @directives = collection.directives
      @dirname = collection.dirname
      @disambig = Util::DisambigFiles.new
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
          f.write(concatenate1(col.clone, e).to_xml)
        end
      end
    end

    def concatenate_outputs(options)
      pres = File.join(@outdir, "collection.presentation.xml")
      options[:format].include?(:pdf) and pdfconv.convert(pres)
      options[:format].include?(:doc) and docconv_convert(pres)
    end

    def concatenate1(out, ext)
      out.directives << "documents-inline"
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
      if (docid = @xml.at("//xmlns:bibdata/xmlns:docidentifier/@type")&.text)
        dt = docid.downcase
      elsif (docid = @xml.at("//xmlns:bibdata/xmlns:docidentifier")&.text)
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

    # @param elm [Nokogiri::XML::Element]
    # @return [String]
    def indexfile_title(elm)
      elm.at(ns("./title"))&.text
    end

    # uses the identifier to label documents; other attributes (title) can be
    # looked up in @files[id][:bibdata]
    #
    # @param elm [Nokogiri::XML::Element]
    # @param builder [Nokogiri::XML::Builder]
    def indexfile_docref(elm, builder)
      return "" unless elm.at(ns("./docref[@index = 'true']"))

      builder.ul { |b| docrefs(elm, b) }
    end

    # @param elm [Nokogiri::XML::Element]
    # @param builder [Nokogiri::XML::Builder]
    def docrefs(elm, builder)
      elm.xpath(ns("./docref[@index = 'true']")).each do |d|
        if m = d.at(ns("./manifest"))
          builder << indexfile(m, ul: false)
        else
        ident = docref_ident(d)
        builder.li do |li|
          li.a href: index_link(d, ident) do |a|
            a << ident.split(/([<>&])/).map do |x|
              /[<>&]/.match?(x) ? x : @c.encode(x, :hexadecimal)
            end.join
          end
        end
      end
      end
    end

    def docref_ident(docref)
      ident = docref.at(ns("./identifier")).children.to_xml
      @c.decode(@isodoc.docid_prefix(nil, ident))
    end

    def index_link(docref, ident)
      if docref["fileref"]
        @files.get(ident, :out_path).sub(/\.xml$/, ".html")
      else "#{docref['id']}.html"
      end
    end

    # single level navigation list, with hierarchical nesting
    #
    # @param elm [Nokogiri::XML::Element]
    # @return [String] XML
    def indexfile(elm, ul: true)
      ret = Nokogiri::HTML::Builder.new do |b|
        b.ul do
          b.li indexfile_title(elm)
          indexfile_docref(elm, b)
          elm.xpath(ns("./manifest")).each do |d|
            b << indexfile(d)
          end
        end
      end
      ret = ret.doc.root
      ul or ret = ret.children
        ret.to_html
    end

    # object to construct navigation out of in Liquid
    def index_object(elm)
      c = elm.xpath(ns("./manifest")).each_with_object([]) do |d, b|
        b << index_object(d)
      end
      c.empty? and c = nil
      r = Nokogiri::HTML::Builder.new do |b|
        indexfile_docref(elm, b)
      end
      r &&= r.doc.root&.to_html&.gsub("\n", " ")
      { title: indexfile_title(elm),
        docrefs: r, children: c }.compact
    end

    def liquid_docrefs
      @xml.xpath(ns("//docref[@index = 'true']")).each_with_object([]) do |d, m|
        ident = d.at(ns("./identifier")).children.to_xml
        ident = @c.decode(@isodoc.docid_prefix(nil, ident))
        title = d.at(ns("./bibdata/title[@type = 'main']")) ||
          d.at(ns("./bibdata/title")) || d.at(ns("./title"))
        m << { "identifier" => ident, "file" => index_link(d, ident),
               "title" => title&.children&.to_xml,
               "level" => d.at(ns("./level"))&.text }
      end
    end
  end
end
