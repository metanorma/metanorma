# frozen_string_literal: true

require_relative "../util/util"

module Metanorma
  # Metanorma collection's manifest
  class CollectionManifest
    # @return [Metanorma::Collection]
    attr_reader :collection, :config

    # @param level [String]
    # @param dir [String]
    # @param title [String, nil]
    # @param docref [Array<Hash{String=>String}>]
    # @param manifest [Array<Metanorma::CollectionManifest>]
    def initialize(config, collection, dir)
      @collection = collection
      @dir = dir
      @disambig = Util::DisambigFiles.new
      @config = manifest_postprocess(config, dir)
    end

    def manifest_postprocess(config, dir)
      manifest_bibdata(config)
      manifest_expand_yaml(config, dir)
      manifest_compile_adoc(config, dir)
      manifest_filexist(config, dir)
      manifest_sectionsplit(config, dir)
      manifest_identifier(config, dir)
      config
    end

    def manifest_bibdata(config)
      b = config.bibdata
      @lang = b&.language&.first || "en"
      @script = b&.script&.first || "Latn"
    end

    GUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

    def manifest_identifier(config, dir)
      no_id = populate_id_from_doc(config, dir)
      config.identifier =
        if no_id && config.file # make file name be id
          @collection.class.resolve_identifier(File.basename(config.file))
        else
          @collection.class.resolve_identifier(config.identifier)
        end
      Array(config.entry).each do |f|
        manifest_identifier(f, dir)
      end
    end

    def populate_id_from_doc(config, dir)
      no_id = /^#{GUID}$/o.match?(config.identifier)
      # GUID assumed to be no identifier supplied
      if no_id && /\.xml$/.match?(config.file) &&
          (i = retrieve_id_from_doc(config.file, dir))
        config.identifier = i
        no_id = false
      end
      no_id
    end

    def retrieve_id_from_doc(file, dir)
      x = Nokogiri::XML(File.read(File.join(dir, file)), &:huge)
      i = x.at("//xmlns:bibdata/xmlns:docidentifier[@primary = 'true']") ||
        x.at("//xmlns:bibdata/xmlns:docidentifier")
      i or return nil
      @doctype ||= i["type"]&.downcase || "standoc"
      load_isodoc
      Util::key(@isodoc.docid_prefix(i["type"], i.text))
    end

    def load_isodoc
      @isodoc and return
      @collection.compile.load_flavor(@doctype)
      @isodoc = Util::load_isodoc(@doctype)
      @isodoc.i18n_init(@lang, @script, nil) # for @i18n.all_parts in docid
    end

    def manifest_sectionsplit(config, dir)
      if config.sectionsplit && !config.file
        config.sectionsplit = nil
        Array(config.entry).each do |e|
          e.attachment and next
          e.sectionsplit = true
        end
      end
      Array(config.entry).each do |f|
        manifest_sectionsplit(f, dir)
      end
    end

    def manifest_filexist(config, dir)
      if config.file
        file = @collection.class.resolve_fileref(dir, config.file)
        @collection.class.check_file_existence(file)
        config.file = Pathname.new(file).relative_path_from(Pathname.new(dir))
      end
      Array(config.entry).each do |f|
        manifest_filexist(f, dir)
      end
    end

    def manifest_expand_yaml(config, dir)
      Array(config.entry).each do |e|
        currdir = dir
        /\.ya?ml$/.match?(e.file) and
          currdir = manifest_expand_yaml_entry(e, dir)
        manifest_expand_yaml(e, currdir)
      end
      config
    end

    def manifest_expand_yaml_entry(entry, dir)
      f = @collection.class.resolve_fileref(dir, entry.file)
      currdir = File.dirname(f)
      @collection.class.check_file_existence(f)
      entry.file = nil
      entry.entry = CollectionConfig::Config.from_yaml(File.read(f)).manifest
      if currdir != dir
        prefix = Pathname.new(currdir).relative_path_from(Pathname.new(dir))
        update_filepaths(entry.entry, prefix.to_s)
      end
      currdir
    end

    def update_filepaths(entry, prefix)
      entry.file && !(Pathname.new entry.file).absolute? and
        entry.file = File.join(prefix, entry.file)
      entry.entry.each do |f|
        update_filepaths(f, prefix)
      end
    end

    def manifest_compile_adoc(config, dir)
      if /\.adoc$/.match?(config.file)
        file = @collection.class.resolve_fileref(dir, config.file)
        config.file = compile_adoc(dir, file, config.file)
      end
      Array(config.entry).each do |f|
        manifest_compile_adoc(f, dir)
      end
    end

    def compile_adoc(dir, resolved_filename, rel_filename)
      compile_adoc_file(dir, resolved_filename)
      set_adoc2xml(rel_filename)
    end

    # @param fileref [String]
    def set_adoc2xml(fileref)
      File.join(
        File.dirname(fileref),
        File.basename(fileref).gsub(/.adoc$/, ".xml"),
      )
    end

    # param filepath [String]
    # @raise [AdocFileNotFoundException]
    def compile_adoc_file(dir, file)
      f = (Pathname.new file).absolute? ? file : File.join(dir, file)
      unless File.exist? f
        raise AdocFileNotFoundException.new "#{f} not found!"
      end

      Util.log("[metanorma] Info: Compiling #{f}...", :info)
      Metanorma::Compile.new
        .compile(f, agree_to_terms: true, no_install_fonts: true,
                    extension_keys: [:xml])
      Util.log("[metanorma] Info: Compiling #{f}...done!", :info)
    end

    def documents(dir = "", mnf = @config)
      Array(mnf.entry).each_with_object({}) do |dr, m|
        if dr.file
          m[Util::key dr.identifier] = documents_add(dir, dr)
        elsif dr.entry
          m.merge! documents(dir, dr)
        end
        m
      end
    end

    def documents_add(dir, docref)
      Document.parse_file(
        Util::rel_path_resolve(dir, docref.file),
        docref.attachment, docref.identifier, docref.index
      )
    end

    def to_xml(builder)
      clean_manifest(@config)
      builder.parent.add_child(@config.to_xml)
    end

    def clean_manifest_bibdata(mnf)
      if mnf.file && !mnf.attachment && !mnf.sectionsplit && @collection &&
          d = @collection.bibdatas[Util::key mnf.identifier]
        mnf.bibdata = d.bibitem.dup
      end
    end

    def clean_manifest_id(mnf)
      if @collection.directives.detect { |d| d.key == "documents-inline" }
        id = @collection.documents.find_index do |k, _|
          k == mnf.identifier
        end
        id and mnf.id = format("doc%<index>09d", index: id)
      end
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
