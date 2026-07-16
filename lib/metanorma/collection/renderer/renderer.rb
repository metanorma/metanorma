require "isodoc"
require "htmlentities"
require "mime/types"
require_relative "fileprocess"
require_relative "../../util/fontist_helper"
require "metanorma-core"
require_relative "../filelookup/filelookup"
require_relative "../multilingual/multilingual"
require_relative "utils"
require_relative "render_word"
require_relative "navigation"
require_relative "svg"
require_relative "../log"

module Metanorma
  class Collection
    class Renderer
      FORMATS = %i[html xml doc pdf pdf-portfolio].freeze

      attr_accessor :isodoc, :isodoc_presxml
      attr_reader :xml, :compile, :compile_options, :documents, :outdir,
                  :manifest, :fatal_errors

      # Run the block with the renderer in nested mode, restoring the previous
      # mode afterwards. Nested mode (used by sectionsplit, which re-enters this
      # renderer's update_xrefs on the pre-split document) preserves unresolved
      # erefs and skips the finalising reference passes.
      def with_nested
        saved = @nested
        @nested = true
        yield
      ensure
        @nested = saved
      end

      # Run the block with the renderer preserving unresolved cross-document
      # references as stubs instead of stripping them -- for an isolated build of
      # a collection member (compiled without the rest of its collection
      # present). Unlike +with_nested+, the ordinary intra-document passes still
      # run (xref_process, svgmap); only the cross-document resolve/strip is
      # turned into preserve, so a later reinflation pass can relink the stubs.
      def with_preserve_unresolved
        saved = @preserve_unresolved
        @preserve_unresolved = true
        yield
      ensure
        @preserve_unresolved = saved
      end

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
        @lang = Array(collection.bibdata.language).first || "en"
        @script = Array(collection.bibdata.script).first || "Latn"
        @locale = @xml.at("//xmlns:bibdata/xmlns:locale")&.text
        @registry = Metanorma::Registry.instance
        @flavor = options[:flavor] || flavor
        @compile = Compile.new
        @compile.load_flavor(@flavor)

        # output processor for flavour
        @isodoc = Util::isodoc_create(Util::taste2flavor(@flavor), @lang,
                                      @script, @xml)
        @isodoc_presxml = Util::isodoc_create(Util::taste2flavor(@flavor),
                                              @lang, @script, @xml,
                                              presxml: true)
        @outdir = dir_name_cleanse(options[:output_folder])
        @format = ::Metanorma::Util.sort_extensions_execution(options[:format])
        @compile_options = options[:compile] || {}
        @compile_options[:install_fonts] = true if options[:install_fonts]
        @log = options[:log]
        @log&.add_msg(METANORMA_LOG_MESSAGES)
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
        # Per-member rendering failures (missing outputs, pooled compile
        # errors), accumulated by file_compile_verify; Collection#render
        # aborts on them once every member has rendered (#586).
        @fatal_errors = []
        @nested = options[:nested]
        # if false, this is the root instance of Renderer
        # if true, then this is not the last time Renderer will be run
        # (e.g. this is sectionsplit)
        # Isolated/incremental build: preserve unresolved cross-document
        # references as stubs instead of resolving or stripping them, so each
        # member compiles independently and a later reinflation pass relinks.
        @preserve_unresolved = options[:preserve_unresolved]
        # Durable content-addressed store for staged artefacts. Opt-in: a plain
        # build sets neither :preserve_unresolved nor :artifact_store_dir, so it
        # gets the no-op Null store and is unaffected. Staging (:preserve_unresolved)
        # defaults the store directory to ArtifactStore::DEFAULT_DIRNAME when no
        # :artifact_store_dir is given, so callers need not name it. (Reinflation
        # reads stored stubs via the manifest, not this object, so it does not
        # trigger the default -- that would only create an empty directory.)
        @artifact_store =
          if (dir = options[:artifact_store_dir]) || options[:preserve_unresolved]
            ArtifactStore.new(dir || ArtifactStore::DEFAULT_DIRNAME)
          else
            NullArtifactStore.new
          end
        # Reinflation pass: the input is a stored stub-bearing Semantic XML that
        # already has intra-doc xrefs and the document suffix applied, so run
        # only the cross-document resolution, not the passes already done.
        @reinflate = options[:reinflate]
        # Cache retention: by default keep only each document's latest artefacts,
        # pruning superseded content-hash versions on write; keep_cache retains
        # every version (history / multiple states side by side).
        @keep_cache = options[:keep_cache]

        @coverpage = options[:coverpage] || collection.coverpage
        @coverpage_pdf_portflio = options[:coverpage_pdf_portfolio] ||
          collection.coverpage_pdf_portfolio || Util::taste2coverpage_pdf_portfolio(@flavor)
        collection.directives = directives_normalise(collection.directives)
        @directives = collection.directives
        # list of files in the collection
        @files = Metanorma::Collection::FileLookup.new(folder, self)
        @files.add_section_split
        isodoc_populate
        create_non_existing_directory(@outdir)
      end

      def directives_normalise(directives)
        @coverpage_pdf_portflio and
          directives = directives_normalise_coverpage_pdf_portfolio(directives)
        directives_normalise_keystore_pdf_portfolio(directives)
      end

      def directives_normalise_coverpage_pdf_portfolio(directives)
        directives_resolve_filepath(directives, "coverpage-pdf-portfolio",
                                    @coverpage_pdf_portflio)
      end

      def directives_normalise_keystore_pdf_portfolio(directives)
        f = directives.find { |d| d.key == "keystore-pdf-portfolio" }
        f.nil? || f.value.nil? and return directives
        directives_resolve_filepath(directives, "keystore-pdf-portfolio",
                                    f.value)
      end

      def directives_resolve_filepath(directives, name, val)
        abs = Pathname.new(val).absolute?
        directives.reject! { |d| d.key == name }
        val = Util::rel_path_resolve(@dirname, val)
        abs or
          val = Pathname.new(val).relative_path_from(Pathname.new(@outdir)).to_s
        directives << ::Metanorma::Collection::Config::Directive
          .new(key: name, value: val)
        directives
      end

      def flush_files
        warn "\n\n\n\n\nDone: #{DateTime.now.strftime('%H:%M:%S')}"
        warn "\nFiles to delete:\n"
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
        cr.rxl(options)
        cr.concatenate(col, options)
        options[:format]&.include?(:html) and cr.coverpage
        cr.flush_files
        cr
      end

      def rxl(options)
        @bibdata or return
        options[:site_generate] and options[:format] << :xml
        options[:format].include?(:rxl) or return
        File.open(File.join(@outdir, "collection.rxl"), "w:UTF-8") do |f|
          f.write(@bibdata.to_xml(bibdata: true))
        end
      end

      def concatenate(col, options)
        warn "\n\n\n\n\nConcatenate: #{DateTime.now.strftime('%H:%M:%S')}"
        concatenate_presentation?(options) and
          options[:format] << :presentation
        concatenate_prep(col, options)
        concatenate_outputs(options)
      end

      def concatenate_presentation?(options)
        !(options[:format] & %i(pdf doc)).empty? ||
          (@directives.detect { |d| d.key == "bilingual" } &&
          options[:format].include?(:html))
      end

      def concatenate_prep(col, options)
        warn options[:format]
        %i(xml presentation).each do |e|
          options[:format].include?(e) or next
          ext = e == :presentation ? "presentation.xml" : e.to_s
          File.open(File.join(@outdir, "collection.#{ext}"), "w:UTF-8") do |f|
            b = concatenate1(col.clone, e).to_xml
            e == :presentation and b = concatenate_presentation(b)
            f.write(b)
          end
        end
      end

      def concatenate_presentation(xml)
        @directives.detect { |d| d.key == "bilingual" } and
          xml = Metanorma::Collection::Multilingual
            .new({ align_cross_elements: %w(p note) }).to_bilingual(xml)
        xml
      end

      def concatenate_outputs(options)
        pres, compile_opts = concatenate_outputs_prep(options)
        warn pp compile_opts
        options[:format].include?(:pdf) and pdfconv(compile_opts).convert(pres)
        options[:format].include?(:"pdf-portfolio") and
          pdfconv(pdf_portfolio_mn2pdf_options)
            .convert(pres, nil, nil,
                     File.join(@outdir, "collection.portfolio.pdf"))
        options[:format].include?(:doc) and docconv_convert(pres)
        bilingual_output(options, pres)
      end

      def concatenate_outputs_prep(_options)
        pres = File.join(@outdir, "collection.presentation.xml")
        fonts = extract_added_fonts(pres)
        if fonts
          # Install fonts before trying to locate them
          font_options = @compile_options.merge({ fonts: fonts })
          ::Metanorma::Util::FontistHelper.install_fonts(@compile.processor,
                                                         font_options)

          mn2pdf = {
            font_manifest: ::Metanorma::Util::FontistHelper
              .location_manifest(@compile.processor, { fonts: fonts }),
          }
        end
        [pres, { fonts: fonts, mn2pdf: mn2pdf }.compact]
      end

      def extract_added_fonts(pres)
        File.exist?(pres) or return
        xml = Nokogiri::XML(File.read(pres, encoding: "UTF-8"), &:huge)
        x = xml.xpath("//*[local-name() = 'presentation-metadata']/" \
                      "*[local-name() = 'fonts']")
        x.empty? and return
        x.map(&:text).join(";")
      end

      def pdf_portfolio_mn2pdf_options
        f1 = @directives.find { |d| d.key == "keystore-pdf-portfolio" }&.value
        f2 = @directives.find do |d|
          d.key == "keystore-password-pdf-portfolio"
        end&.value
        {  "pdf-portfolio": "true", pdfkeystore: f1,
           pdfkeystorepassword: f2 }.compact
      end

      def bilingual_output(options, pres)
        @directives.detect { |d| d.key == "bilingual" } &&
          options[:format].include?(:html) and
          Metanorma::Collection::Multilingual.new(
            { flavor: Util::taste2flavor(flavor).to_sym,
              converter_options: PdfOptionsNode.new(Util::taste2flavor(flavor),
                                                    @compile_options),
              outdir: @outdir },
          ).to_html(pres)
      end

      def concatenate1(out, ext)
        out.directives << ::Metanorma::Collection::Config::Directive
          .new(key: "documents-inline")
        out.bibdatas.each_key do |ident|
          id = @isodoc.docid_prefix(nil, ident.dup)
          @files.get(id, :attachment) and next
          # A non-attachment document with no compiled output for THIS format
          # cannot be inlined: leaving it in place serialises as a bibdata-only,
          # namespace-less <metanorma> that mn2pdf silently drops. Skip loudly
          # rather than crash on a nil path or corrupt the collection PDF.
          # (Sectionsplit parents get a :presentation output upstream, so they
          # inline whole for the PDF/presentation path.)
          outputs = @files.get(id, :outputs)
          # The registered path may exist without the file: a member whose
          # rendering failed registers its intended outputs but writes
          # nothing (#586), so check the disk, not just the registration.
          if outputs.nil? || outputs[ext].nil? || !File.exist?(outputs[ext])
            warn "[metanorma] collection document '#{id}' has no compiled " \
                 "#{ext} output to inline; skipping (its doc-container would " \
                 "otherwise be bibdata-only)."
            next
          end
          out.documents[Util::key id] =
            Metanorma::Collection::Document.raw_file(outputs[ext])
        end
        out
      end

      # TODO: infer flavor from publisher when available
      def flavor
        dt = @xml.at("//bibdata/ext/flavor")&.text or return "standoc"
        @registry.alias(dt.to_sym)&.to_s || dt
      end

      # populate liquid template of ARGV[1] with metadata extracted from
      # collection manifest
      def coverpage
        @coverpage or return
        @coverpage_path = Util::rel_path_resolve(@dirname, @coverpage)
        warn "\n\n\n\n\nCoverpage: #{DateTime.now.strftime('%H:%M:%S')}"
        File.open(File.join(@outdir, "index.html"), "w:UTF-8") do |f|
          f.write @isodoc.populate_template(File.read(@coverpage_path))
        end
      end
    end
  end
end
