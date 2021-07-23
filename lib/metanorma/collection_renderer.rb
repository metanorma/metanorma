# frozen_string_literal: true

require "isodoc"
require_relative "collection_fileprocess"
require_relative "fontist_utils"
require_relative "util"

module Metanorma
  # XML collection renderer
  class CollectionRenderer
    FORMATS = %i[html xml doc pdf].freeze

    # This is only going to render the HTML collection
    # @param xml [Metanorma::Collection] input XML collection
    # @param folder [String] input folder
    # @param options [Hash]
    # @option options [String] :coverpage cover page HTML (Liquid template)
    # @option options [Array<Symbol>] :format list of formats (xml,html,doc,pdf)
    # @option options [String] :ourput_folder output directory
    #
    # We presuppose that the bibdata of the document is equivalent to that of
    # the collection, and that the flavour gem can sensibly process it. We may
    # need to enhance metadata in the flavour gems isodoc/metadata.rb with
    # collection metadata
    def initialize(collection, folder, options = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      check_options options
      @xml = Nokogiri::XML collection.to_xml # @xml is the collection manifest
      @lang = @xml&.at(ns("//bibdata/language"))&.text || "en"
      @script = @xml&.at(ns("//bibdata/script"))&.text || "Latn"
      @doctype = doctype
      require "metanorma-#{@doctype}"

      # output processor for flavour
      @isodoc = isodoc

      @outdir = options[:output_folder]
      @coverpage = options[:coverpage]
      @format = Util.sort_extensions_execution(options[:format])
      @compile_options = options[:compile] || {}
      @compile_options[:no_install_fonts] = true if options[:no_install_fonts]
      @log = options[:log]
      @documents = collection.documents
      @directives = collection.directives
      @disambig = Util::DisambigFiles.new
      @compile = Compile.new

      # list of files in the collection
      @files = read_files folder
      isodoc_populate(@isodoc)
      FileUtils.rm_rf @outdir
      FileUtils.mkdir_p @outdir
    end

    # @param col [Metanorma::Collection] XML collection
    # @param options [Hash]
    # @option options [String] :coverpage cover page HTML (Liquid template)
    # @option options [Array<Synbol>] :format list of formats
    # @option options [Strong] :ourput_folder output directory
    def self.render(col, options = {})
      folder = File.dirname col.file
      #require "byebug"; byebug
      warn "\n\n\n\n\nRender Init: #{DateTime.now.strftime('%H:%M:%S')}"
      cr = new(col, folder, options)
      warn "\n\n\n\n\nRender Files: #{DateTime.now.strftime('%H:%M:%S')}"
      cr.files
      warn "\n\n\n\n\nConcatenate: #{DateTime.now.strftime('%H:%M:%S')}"
      cr.concatenate(col, options)
      warn "\n\n\n\n\nCoverpage: #{DateTime.now.strftime('%H:%M:%S')}"
      cr.coverpage if options[:format]&.include?(:html)
      warn "\n\n\n\n\nDone: #{DateTime.now.strftime('%H:%M:%S')}"
    end

    def concatenate(col, options)
      options[:format] << :presentation if options[:format].include?(:pdf)
      options[:format].uniq.each do |e|
        next unless %i(presentation xml).include?(e)

        ext = e == :presentation ? "presentation.xml" : e.to_s
        out = col.clone
        out.directives << "documents-inline"
        out.documents.each_key do |id|
          next if @files[id][:attachment]

          filename = @files[id][:outputs][e]
          out.documents[id] = Metanorma::Document.raw_file(filename)
        end
        File.open(File.join(@outdir, "collection.#{ext}"), "w:UTF-8") do |f|
          f.write(out.to_xml)
        end
      end
      options[:format].include?(:pdf) and
        pdfconv.convert(File.join(@outdir, "collection.presentation.xml"))
    end

    def pdfconv
      doctype = @doctype.to_sym
      x = Asciidoctor.load nil, backend: doctype
      x.converter.pdf_converter(PdfOptionsNode.new(doctype, @compile_options))
    end

    class PdfOptionsNode
      def initialize(doctype, options)
        doc_proc = Metanorma::Registry.instance.find_processor(doctype)
        @font_locations = FontistUtils.fontist_font_locations(doc_proc, options)
      end

      def attr(key)
        if key == "mn2pdf-font-manifest-file" && @font_locations
          @font_locations.path
        end
      end
    end

    # Dummy class
    class Dummy
      def attr(_key); end
    end

    # The isodoc class for the metanorma flavour we are using
    def isodoc
      x = Asciidoctor.load nil, backend: @doctype.to_sym
      isodoc = x.converter.html_converter(Dummy.new)
      isodoc.i18n_init(@lang, @script) # read in internationalisation
      isodoc.metadata_init(@lang, @script, isodoc.i18n)
      isodoc.info(@xml, nil)
      isodoc
    end

    def isodoc_populate(isodoc)
      # create the @meta class of isodoc, with "navigation" set to the index bar
      # extracted from the manifest
      nav = indexfile(@xml.at(ns("//manifest")))
      i18n = isodoc.i18n
      i18n.set("navigation", nav)
      isodoc.metadata_init(@lang, @script, i18n)
      # populate the @meta class of isodoc with the various metadata fields
      # native to the flavour; used to populate Liquid
      isodoc.info(@xml, nil)
      isodoc
    end

    # infer the flavour from the first document identifier; relaton does that
    def doctype
      if (docid = @xml&.at(ns("//bibdata/docidentifier/@type"))&.text)
        dt = docid.downcase
      elsif (docid = @xml&.at(ns("//bibdata/docidentifier"))&.text)
        dt = docid.sub(/\s.*$/, "").lowercase
      else return "standoc"
      end
      @registry = Metanorma::Registry.instance
      @registry.alias(dt.to_sym)&.to_s || dt
    end

    def ns(xpath)
      IsoDoc::Convert.new({}).ns(xpath)
    end

    # populate liquid template of ARGV[1] with metadata extracted from
    # collection manifest
    def coverpage
      return unless @coverpage

      File.open(File.join(@outdir, "index.html"), "w:UTF-8") do |f|
        f.write @isodoc.populate_template(File.read(@coverpage))
      end
    end

    # @param elm [Nokogiri::XML::Element]
    # @return [String]
    def indexfile_title(elm)
      lvl = elm&.at(ns("./level"))&.text&.capitalize
      lbl = elm&.at(ns("./title"))&.text
      "#{lvl}#{lvl && lbl ? ': ' : ''}#{lbl}"
    end

    # uses the identifier to label documents; other attributes (title) can be
    # looked up in @files[id][:bibdata]
    #
    # @param elm [Nokogiri::XML::Element]
    # @param builder [Nokogiri::XML::Builder]
    def indexfile_docref(elm, builder)
      return "" unless elm.at(ns("./docref"))

      builder.ul { |b| docrefs(elm, b) }
    end

    # @param elm [Nokogiri::XML::Element]
    # @param builder [Nokogiri::XML::Builder]
    def docrefs(elm, builder)
      elm.xpath(ns("./docref")).each do |d|
        ident = d.at(ns("./identifier")).children.to_xml
        builder.li do |li|
          li.a **{ href: index_link(d, ident) } do |a|
            a << ident
          end
        end
      end
    end

    def index_link(docref, ident)
      if docref["fileref"]
        @files[ident][:out_path].sub(/\.xml$/, ".html")
      else "#{docref['id']}.html"
      end
    end

    # single level navigation list, with hierarchical nesting
    # if multiple lists are needed as separate HTML fragments, multiple
    # instances of this function will be needed,
    # and associated to different variables in the call to @isodoc.metadata_init
    # (including possibly an array of HTML fragments)
    #
    # @param elm [Nokogiri::XML::Element]
    # @return [String] XML
    def indexfile(elm)
      Nokogiri::HTML::Builder.new do |b|
        b.ul do
          b.li indexfile_title(elm)
          indexfile_docref(elm, b)
          elm.xpath(ns("./manifest")).each do |d|
            b << indexfile(d)
          end
        end
      end.doc.root.to_html
    end

    private

    def format_sort(formats)
      ret = []
      formats.include?(:xml) and ret << :xml
      formats.include?(:presentation) and ret << :presentation
      a = %i(presentation xml)
      ret + formats.reject { |i| a.include? i }
    end

    # @param options [Hash]
    # @raise [ArgumentError]
    def check_options(options)
      unless options[:format].is_a?(Array) && (FORMATS & options[:format]).any?
        raise ArgumentError, "Need to specify formats (xml,html,pdf,doc)"
      end
    end
  end
end
