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

    # @param elm [Nokogiri::XML::Element]
    # @return [String]
    def indexfile_title(entry)
      if entry.bibdata
        x = entry.bibdata.title.detect { |t| t.type == "main" } ||
          entry.bibdata.title.first
        x.title.content
      else
        entry.title
      end
    end

    # uses the identifier to label documents; other attributes (title) can be
    # looked up in @files[id][:bibdata]
    #
    # @param mnf [Collection::Manifest]
    # @param builder [Nokogiri::XML::Builder]
    def indexfile_docref(mnf, builder)
      Array(mnf.entry).detect(&:index) or return ""
      builder.ul { |b| docrefs(mnf, b) }
    end

    def docrefs(mnf, builder)
      ident = docref_ident(mnf)
      builder.li do |li|
        li.a href: index_link(mnf, ident) do |a|
          a << ident.split(/([<>&])/).map do |x|
            /[<>&]/.match?(x) ? x : @c.encode(x, :hexadecimal)
          end.join
        end
      end
    end

    def docref_ident(docref)
      ident = docref.identifier.dup
      @c.decode(@isodoc.docid_prefix(nil, ident))
    end

    def index_link(docref, ident)
      if docref.file
        @files.get(ident, :out_path).sub(/\.xml$/, ".html")
      else "#{docref.id}.html"
      end
    end

    # single level navigation list, with hierarchical nesting
    def indexfile(mnf)
      mnfs = Array(mnf)
      mnfs.empty? and return ""
      mnfs.map { |m| "<ul>#{indexfile1(m)}</ul>" }.join("\n")
    end

    def index?(mnf)
      mnf.index and return true
      mnf.entry.detect { |e| index?(e) }
    end

    def indexfile1(mnf)
      index?(mnf) or return ""
      cleanup_indexfile1(build_indexfile1(mnf))
    end

    def build_indexfile1(mnf)
      Nokogiri::HTML::Builder.new do |b|
        if mnf.file then docrefs(mnf, b)
        else
          b.li do |l|
            l << indexfile_title(mnf)
            l.ul do |u|
              Array(mnf.entry).each { |e| u << indexfile1(e) }
            end
          end
        end
      end
    end

    def cleanup_indexfile1(ret)
      ret = ret.doc.root
      ret.xpath("/ul").each do |u|
        if u.at("./li/ul") && !u.at("./li[text()]")
          u.replace(u.xpath("./li/ul"))
        end
      end
      ret.to_html
    end

    # object to construct navigation out of in Liquid
    def index_object(mnf)
      mnf = Array(mnf).first
      ret = { title: indexfile_title(mnf), level: mnf.type,
              docrefs: index_object_docrefs(mnf),
              children: index_object_children(mnf) }.compact
      ret.keys == [:children] and ret = ret[:children]
      ret
    end

    def index_object_children(mnf)
      nonfiles = Array(mnf.entry).reject(&:file)
      c = nonfiles.each_with_object([]) do |d, b|
        b << index_object(d)
      end.flatten
      c.empty? and c = nil
      c
    end

    def index_object_docrefs(mnf)
      files = Array(mnf.entry).select(&:file)
      files.empty? and return nil
      r = Nokogiri::HTML::Builder.new do |b|
        b.ul do |u|
          files.each { |f| docrefs(f, u) }
        end
      end
      r.doc.root&.to_html&.gsub("\n", " ")
    end

    def liquid_docrefs(mnfs)
      Array(mnfs).select(&:index).each_with_object([]) do |d, m|
        if d.file
          ident = @c.decode(@isodoc.docid_prefix(nil, d.identifier.dup))
          m << { "identifier" => ident, "file" => index_link(d, ident),
                 "title" => indexfile_title(d), "level" => d.type }
        else
          liquid_docrefs(d.entry).each { |m1| m << m1 }
        end
      end
    end
  end
end
