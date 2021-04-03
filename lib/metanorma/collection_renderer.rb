# frozen_string_literal: true

require "isodoc"
require_relative "./collection_fileprocess"

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
    def initialize(xml, folder, options = {}) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      check_options options
      @xml = Nokogiri::XML xml # @xml is the collection manifest
      @lang = @xml&.at(ns("//bibdata/language"))&.text || "en"
      @script = @xml&.at(ns("//bibdata/script"))&.text || "Latn"
      @doctype = doctype
      require "metanorma-#{@doctype}"

      # output processor for flavour
      @isodoc = isodoc

      @outdir = options[:output_folder]
      @coverpage = options[:coverpage]
      @format = options[:format]
      @compile_options = options[:compile] || {}
      @log = options[:log]

      # list of files in the collection
      @files = read_files folder
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
      cr = new(col.to_xml, folder, options)
      cr.files
      cr.concatenate(col, options)
      cr.coverpage if options[:format]&.include?(:html)
    end

    def concatenate(col, options)
      options[:format] << :presentation if options[:format].include?(:pdf)
      options[:format].uniq.each do |e|
        next unless %i(presentation xml).include?(e)
        ext = e == :presentation ? "presentation.xml" : e.to_s
        out = col.clone
        out.directives << "documents-inline"
        out.documents.keys.each do |id|
          next if @files[id][:attachment]
          filename = @files[id][:outputs][e]
          out.documents[id] = Metanorma::Document.raw_file(filename)
        end
        File.open(File.join(@outdir, "collection.#{ext}"), "w:UTF-8") { |f| f.write(out.to_xml) }
      end
      options[:format].include?(:pdf) and
        pdfconv.convert(File.join(@outdir, "collection.presentation.xml"))
    end

    def pdfconv
      x = Asciidoctor.load nil, backend: @doctype.to_sym
      x.converter.pdf_converter(Dummy.new)
    end

    # Dummy class
    class Dummy
      def attr(_xyz); end
    end

    # The isodoc class for the metanorma flavour we are using
    def isodoc # rubocop:disable Metrics/MethodLength
      x = Asciidoctor.load nil, backend: @doctype.to_sym
      isodoc = x.converter.html_converter(Dummy.new)
      isodoc.i18n_init(@lang, @script) # read in internationalisation
      # create the @meta class of isodoc, with "navigation" set to the index bar
      # extracted from the manifest
      nav = indexfile(@xml.at(ns("//manifest")))
      i18n = isodoc.i18n
      i18n.set(:navigation, nav)
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
        identifier = d.at(ns("./identifier")).text
        link = if d["fileref"] then d["fileref"].sub(/\.xml$/, ".html")
               else d["id"] + ".html"
               end
        builder.li { builder.a identifier, href: link }
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

    # @param options [Hash]
    # @raise [ArgumentError]
    def check_options(options)
      unless options[:format].is_a?(Array) && (FORMATS & options[:format]).any?
        raise ArgumentError, "Need to specify formats (xml,html,pdf,doc)"
      end
      return if !options[:format].include?(:html) || options[:coverpage]
      raise ArgumentError, "Need to specify a coverpage to render HTML"
    end
  end
end
