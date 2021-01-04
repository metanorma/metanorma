# frozen_string_literal: true

require "isodoc"

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

    # hash for each document in collection of document identifier to:
    # document reference (fileref or id), type of document reference,
    # and bibdata entry for that file
    # @param path [String] path to collection
    # @return [Hash{String=>Hash}]
    def read_files(path) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      files = {}
      @xml.xpath(ns("//docref")).each do |d|
        identifier = d.at(ns("./identifier")).text
        files[identifier] = if d["fileref"]
                              { type: "fileref",
                                ref: File.join(path, d["fileref"]) }
                            else { type: "id", ref: d["id"] }
                            end
        file, _filename = targetfile(files[identifier], true)
        xml = Nokogiri::XML(file)
        add_document_suffix(identifier, xml)
        files[identifier][:anchors] = read_anchors(xml)
        files[identifier][:bibdata] = xml.at(ns("//bibdata"))
      end
      files
    end

    def add_suffix_to_attributes(doc, suffix, tag_name, attribute_name)
      doc.xpath(ns("//#{tag_name}[@#{attribute_name}]")).each do |elem|
        elem.attributes[attribute_name].value =
          "#{elem.attributes[attribute_name].value}_#{suffix}"
      end
    end

    def add_document_suffix(identifier, doc)
      document_suffix = Asciidoctor::Standoc::Cleanup.to_ncname(identifier)
      [%w[* id],
      %w[* bibitemid],
      %w[review from],
      %w[review to],
      %w[index to],
      %w[xref target],
      %w[callout target]]
      .each do |(tag_name, attribute_name)|
        add_suffix_to_attributes(doc, document_suffix, tag_name, attribute_name)
      end
    end

    # map locality type and label (e.g. "clause" "1") to id = anchor for
    # a document
    def read_anchors(xml)
      ret = {}
      xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.i18n, {})
      xrefs.parse xml
      xrefs.get.each do |k, v|
        v[:label] && v[:type] || next
        ret[v[:type]] ||= {}
        ret[v[:type]][v[:label]] = k
      end
      ret
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

    # return file contents + output filename for each file in the collection,
    # given a docref entry
    # @param data [Hash]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def targetfile(data, read = false)
      if data[:type] == "fileref" then ref_file data[:ref], read
      else xml_file data[:id], read
      end
    end

    # @param ref [String]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def ref_file(ref, read)
      file = File.read(ref, encoding: "utf-8") if read
      filename = ref.sub(/\.xml$/, ".html")
      [file, filename]
    end

    # @param id [String]
    # @param read [Boolean]
    # @return [Array<String, nil>]
    def xml_file(id, read)
      file = @xml.at(ns("//doc-container[@id = '#{id}']")).to_xml if read
      filename = id + ".html"
      [file, filename]
    end

    # @param bib [Nokogiri::XML::Element]
    # @param identifier [String]
    def update_bibitem(bib, identifier) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      docid = bib&.at(ns("./docidentifier"))&.text
      unless @files[docid]
        warn "Cannot find crossreference to document #{docid} in document "\
          "#{identifier}!"
        abort
      end
      id = bib["id"]
      newbib = bib.replace(@files[docid][:bibdata])
      newbib.name = "bibitem"
      newbib["id"] = id
      newbib["hidden"] = "true"
      newbib&.at(ns("./ext"))&.remove
      _file, url = targetfile(@files[docid], false)
      uri_node = Nokogiri::XML::Node.new "uri", newbib
      uri_node[:type] = "citation"
      uri_node.content = url
      newbib.at(ns("./docidentifier")).previous = uri_node
    end

    # TODO: update crossreferences to other files in the selection
    # repo(current-metanorma-collection/ISO 17301-1:2016)
    # replaced by
    # bibdata of "ISO 17301-1:2016" in situ as bibitem
    # Any erefs to that bibitem id are replaced with relative URL
    # Preferably with anchor, and is a job to realise dynamic lookup of
    # localities
    # @param file [String] XML content
    # @param identifier [String] docid
    # @return [String] XML content
    def update_xrefs(file, identifier)
      docxml = Nokogiri::XML(file)
      add_document_suffix(identifier, docxml)
      docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
        docid = b&.at(ns("./docidentifier[@type = 'repository']"))&.text
        next unless docid && %r{^current-metanorma-collection/}.match(docid)

        update_bibitem(b, identifier)
        update_anchors(b, docxml, docid)
      end
      docxml.xpath(ns("//references[not(./bibitem[not(@hidden) or @hidden = 'false'])]")).each do |f|
        f["hidden"] = "true"
      end
      docxml.to_xml
    end

    # if there is a crossref to another document, with no anchor, retrieve the
    # anchor given the locality, and insert it into the crossref
    def update_anchors(bib, docxml, _id) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      docid = bib&.at(ns("./docidentifier"))&.text
      docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
        e.at(ns(".//locality[@type = 'anchor']")).nil? || next
        ins = e.at(ns("./localityStack")) || next
        type = ins&.at(ns("./locality/@type"))&.text
        ref = ins&.at(ns("./locality/referenceFrom"))&.text
        (anchor = @files[docid][:anchors][type][ref]) || next
        ref_from = Nokogiri::XML::Node.new "referenceFrom", bib
        ref_from.content = anchor.sub(/^_/, "")
        locality = Nokogiri::XML::Node.new "locality", bib
        locality[:type] = "anchor"
        locality.add_child ref_from
        ins << locality
      end
    end

    # process each file in the collection
    # files are held in memory, and altered as postprocessing
    def files # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      @files.each do |identifier, x|
        file, filename = targetfile(x, true)
        file = update_xrefs(file, identifier)
        Tempfile.open(["collection", ".xml"], encoding: "utf-8") do |f|
          f.write(file)
          f.close
          # warn "metanorma compile -x html #{f.path}"
          c = Compile.new
          options = {format: :asciidoc, extension_keys: @format}.merge @compile_options
          c.compile f.path, options
          @files[identifier][:outputs] = {}
          @format.each do |e|
            ext = c.processor.output_formats[e]
            fn = File.basename(filename).sub(/(?<=\.)[^\.]+$/, ext.to_s)
            FileUtils.mv f.path.sub(/\.xml$/, ".#{ext}"), File.join(@outdir, fn)
            @files[identifier][:outputs][e] = File.join(@outdir, fn)
          end
        end
      end
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
