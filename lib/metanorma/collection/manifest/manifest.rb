# frozen_string_literal: true

require_relative "../../util/util"

module Metanorma
  class Collection
    class Manifest
      # @return [Metanorma::Collection]
      attr_reader :collection, :config, :lang, :script

      # @param level [String]
      # @param dir [String]
      # @param title [String, nil]
      # @param docref [Array<Hash{String=>String}>]
      # @param manifest [Array<Metanorma::Collection::Manifest>]
      def initialize(config, collection, dir)
        #require "debug"; binding.b
        @collection = collection
        @dir = dir
        @disambig = ::Metanorma::Collection::Util::DisambigFiles.new
        @config = manifest_postprocess(config)
      end

      def manifest_postprocess(config)
        #require "debug"; binding.b
        manifest_bibdata(config)
        manifest_expand_yaml(config, @dir)
        manifest_compile_adoc(config)
        manifest_filexist(config)
        manifest_sectionsplit(config)
        manifest_identifier(config)
        config
      end

      def manifest_bibdata(config)
        b = config.bibdata
        @lang = b&.language&.first || "en"
        @script = b&.script&.first || "Latn"
      end

      GUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

      def manifest_identifier(config)
        no_id = populate_id_from_doc(config)
        config.identifier =
          if no_id && config.file # make file name be id
            @collection.class.resolve_identifier(File.basename(config.file))
          else
            @collection.class.resolve_identifier(config.identifier)
          end
        Array(config.entry).each do |f|
          manifest_identifier(f)
        end
      end

      def populate_id_from_doc(config)
        no_id = /^#{GUID}$/o.match?(config.identifier)
        # GUID assumed to be no identifier supplied
        if no_id && /\.xml$/.match?(config.file) &&
            (i = retrieve_id_from_doc(config.file))
          config.identifier = i
          no_id = false
        end
        no_id
      end

      def retrieve_id_from_doc(file)
        x = Nokogiri::XML(File.read(File.join(@dir, file)), &:huge)
        i = x.at("//xmlns:bibdata/xmlns:docidentifier[@primary = 'true']") ||
          x.at("//xmlns:bibdata/xmlns:docidentifier")
        i or return nil
        @flavor = @collection.flavor
        load_isodoc
        Util::key(@isodoc.docid_prefix(i["type"], i.text))
      end

      def load_isodoc
        @isodoc and return
        @collection.compile.load_flavor(@flavor)
        @isodoc = Util::load_isodoc(@flavor)
        @isodoc.i18n_init(@lang, @script, nil) # for @i18n.all_parts in docid
      end

      def manifest_sectionsplit(config)
        if config.sectionsplit && !config.file
          config.sectionsplit = nil
          Array(config.entry).each do |e|
            e.attachment and next
            e.sectionsplit = true
          end
        end
        Array(config.entry).each do |f|
          manifest_sectionsplit(f)
        end
      end

      def manifest_filexist(config)
        if config.file
        #require "debug"; binding.b
          file = @collection.class.resolve_fileref(@dir, config.file)
          @collection.class.check_file_existence(file)
          config.file = Pathname.new(file).relative_path_from(Pathname.new(@dir))
        end
        Array(config.entry).each do |f|
          manifest_filexist(f)
        end
      end

      def manifest_expand_yaml(config, dir)
        Array(config.entry).each do |e|
          currdir = dir
          /\.ya?ml$/.match?(e.file) and
            currdir = manifest_expand_yaml_entry(e, dir)
          #require "debug"; binding.b
          manifest_expand_yaml(e, currdir)
        end
        config
      end

      def manifest_expand_yaml_entry(entry, dir)
        f = @collection.class.resolve_fileref(dir, entry.file)
        currdir = File.dirname(f)
        @collection.class.check_file_existence(f)
        entry.file = nil
        #require 'debug'; binding.b
        entry.entry = ::Metanorma::Collection::Config::Config.from_yaml(File.read(f)).manifest
        if currdir != dir
          #require "debug"; binding.b
          prefix = Pathname.new(currdir).relative_path_from(Pathname.new(dir))
          update_filepaths(entry.entry, prefix.to_s)
        end
        currdir
      end

      def update_filepaths(entry, prefix)
        #require "debug"; binding.b
        entry.file && !(Pathname.new entry.file).absolute? and
          entry.file = File.join(prefix, entry.file)
        entry.entry.each do |f|
          update_filepaths(f, prefix)
        end
      end

      def manifest_compile_adoc(config)
        if /\.adoc$/.match?(config.file)
          file = @collection.class.resolve_fileref(@dir, config.file)
          config.file = compile_adoc(file, config.file)
        end
        Array(config.entry).each do |f|
          manifest_compile_adoc(f)
        end
      end

      def compile_adoc(resolved_filename, rel_filename)
        compile_adoc_file(resolved_filename)
        set_adoc2xml(rel_filename)
      end

      # @param fileref [String]
      def set_adoc2xml(fileref)
        File.join(
          File.dirname(fileref),
          File.basename(fileref).gsub(/\.adoc$/, ".xml"),
        )
      end

      # param filepath [String]
      # @raise [AdocFileNotFoundException]
      def compile_adoc_file(file)
        f = (Pathname.new file).absolute? ? file : File.join(@dir, file)
        File.exist?(f) or raise AdocFileNotFoundException.new "#{f} not found!"
        compile_adoc_file?(file) or return
        ::Metanorma::Util.log("[metanorma] Info: Compiling #{f}...", :info)
        ::Metanorma::Compile.new
          .compile(f, agree_to_terms: true, install_fonts: false,
                      extension_keys: [:xml])
        ::Metanorma::Util.log("[metanorma] Info: Compiling #{f}...done!", :info)
      end

      def compile_adoc_file?(file)
        @collection.directives.detect do |d|
          d.key == "recompile-xml"
        end and return true
        !File.exist?(file.sub(/\.adoc$/, ".xml"))
      end

      def documents(mnf = @config)
        Array(mnf.entry).each_with_object({}) do |dr, m|
          if dr.file
            m[Util::key dr.identifier] = documents_add(dr)
          elsif dr.entry
            m.merge! documents(dr)
          end
          m
        end
      end

      def documents_add(docref)
        ::Metanorma::Collection::Document.parse_file(
          Util::rel_path_resolve(@dir, docref.file),
          docref.attachment, docref.identifier, docref.index
        )
      end

      def to_xml(builder = nil)
        clean_manifest(@config)
        if builder
          builder.parent.add_child(@config.to_xml)
        else
          @config.to_xml
        end
      end

      def clean_manifest_bibdata(mnf)
        if mnf.file && !mnf.attachment && !mnf.sectionsplit && @collection &&
            d = @collection.bibdatas[Util::key mnf.identifier]
          mnf.bibdata = d.bibitem.dup
        end
      end

      def clean_manifest_id(mnf)
        @collection.directives.detect do |d|
          d.key == "documents-inline"
        end or return
        id = @collection.documents.find_index do |k, _|
          k == mnf.identifier
        end
        id and mnf.id = format("doc%<index>09d", index: id)
      end

      def clean_manifest(mnf)
        clean_manifest_bibdata(mnf)
        # mnf.file &&= @disambig.strip_root(mnf.file)
        clean_manifest_id(mnf)
        Array(mnf.entry).each { |e| clean_manifest(e) }
      end

      # @return [Array<Hash{String=>String}>]
      def docrefs
        @config.entry
      end

      def docref_by_id(docid)
        @config.entry.detect { |k| k.identifier == docid } ||
          @config.entry.detect { |k| /^#{k.identifier}/ =~ docid }
      end
    end
  end
end
