# frozen_string_literal: true

require_relative "util"

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
      require  "debug"; binding.b
      manifest_expand_yaml(config, dir)
      manifest_compile_adoc(config, dir)
      manifest_filexist(config, dir)
      manifest_sectionsplit(config, dir)
      manifest_identifier(config, dir)
      require  "debug"; binding.b
      config
    end

    def manifest_identifier(config, dir)
      config.identifier = if !config.identifier && config.file
                            @collection.class
                              .resolve_identifier(File.dirname(config.file))
                          else
                            @collection.class
                              .resolve_identifier(config.identifier)
                          end
      Array(config.entry).each do |f|
        manifest_identifier(f, dir)
      end
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
        if /\.ya?ml$/.match?(e.file)
          f = @collection.class.resolve_fileref(dir, e.file)
          currdir = File.dirname(f)
          @collection.class.check_file_existence(f)
          e.file = nil
          e.entry = CollectionConfig::Config.from_yaml(File.read(f)).manifest
          if currdir != dir
            prefix = Pathname.new(currdir).relative_path_from(Pathname.new(dir))
            update_filepaths(e.entry, prefix.to_s)
          end
        end
        manifest_expand_yaml(e, currdir)
      end
      config
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

    class << self
      # @param mnf [Nokogiri::XML::Element]
      # @return [Metanorma::CollectionManifest]
      def from_yaml(mnf, dir) # KILL
        manifest = RelatonBib.array(mnf["manifest"]).map do |m|
          from_yaml m, dir
        end
        docref = RelatonBib.array mnf["docref"]
        new(mnf["level"], dir, mnf["title"], parse_docrefs_yaml(docref, dir),
            manifest)
      end

      # @param mnf [Nokogiri::XML::Element]
      # @return [Metanorma::CollectionManifest]
      def from_xml(mnf, dir) # KILL
        level = mnf.at("level").text
        title = mnf.at("title")&.text
        manifest = mnf.xpath("xmlns:manifest").map { |m| from_xml(m, dir) }
        new(level, dir, title, parse_docrefs_xml(mnf, dir), manifest)
      end

      private

      # We will deal with YAML files on sighting them,
      # before passing the manifest on to anything else
      def parse_docrefs_yaml(docrefs, dir) # KILL
        docrefs.map do |dr|
          h = {}
          h["identifier"] =
            dr["identifier"] || UUIDTools::UUID.random_create.to_s
          dr["manifest"] and h["manifest"] =
                               from_yaml(dr["manifest"].first, dir)
          compile_adoc(dr, dir)
          %w(fileref url attachment sectionsplit index presentation-xml)
            .each do |k|
            dr.has_key?(k) and h[k] = dr[k]
          end
          h
        end
      end

      # @param mnf [Nokogiri::XML::Element]
      # @return [Hash{String=>String}]
      def parse_docrefs_xml(mnf, dir) # KILL
        mnf.xpath("xmlns:docref").map do |dr|
          h = { "identifier" => parse_docrefs_xml_id(dr) }
          %i(fileref fileref_original url attachment sectionsplit
             index).each do |s|
            h[s.to_s] = dr[s] if dr[s]
          end
          m = dr.at("manifest") and h["manifest"] = from_xml(m, dir)
          h["presentation-xml"] = dr[:presentationxml] if dr[:presentationxml]
          h
        end
      end

      def parse_docrefs_xml_id(docref) # KILL
        if i = docref.at("identifier")
          i.children.to_xml
        else UUIDTools::UUID.random_create
        end
      end
    end

    # @param col [Metanorma::Collection]
    def collection=(col)
      @collection = col
      # @manifest.each { |mnf| mnf.collection = col } # KILL
    end

    # @param dir [String] path to collection
    # @return [Hash<String, Metanorma::Document>]
    def documents(dir = "") # KILL
      docs = @docref.each_with_object({}) do |dr, m|
        if dr["fileref"]
          m[Util::key dr["identifier"]] = documents_add(dir, dr)
        elsif dr["manifest"]
          m.merge! dr["manifest"].documents(dir)
        end
        m
      end
      # no manifest/manifest any more
      @manifest.reduce(docs) do |mem, mnf|
        mem.merge mnf.documents(dir)
      end
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

    def documents_add(dir, docref) # KILL
      Document.parse_file(
        Util::rel_path_resolve(dir, docref["fileref"]),
        docref["attachment"], docref["identifier"], docref["index"]
      )
    end

    def documents_add(dir, docref)
      Document.parse_file(
        Util::rel_path_resolve(dir, docref.file),
        docref.attachment, docref.identifier, docref.index
      )
    end

    # @param builder [Nokogiri::XML::Builder]
    def to_xml(builder) # KILL
      builder.manifest do |b|
        b.level @level
        b.title @title if @title
        docref_to_xml b
        @manifest&.each { |m| m.to_xml b }
      end
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

    # @return [Array<Hash{String=>String}>] # KILL
    def docrefs
      @docrefs and return @docrefs
      drfs = @docref.map { |dr| dr }
      # no manifest/manifest
      @manifest.reduce(drfs) do |mem, mnf|
        mem + mnf.docrefs
      end
    end

    # @return [Array<Hash{String=>String}>]
    def docrefs
      @config.entry
    end

    def docref_by_id(docid) # KILL
      refs = docrefs
      dref = refs.detect { |k| k["identifier"] == docid }
      dref || docrefs.detect { |k| /^#{k['identifier']}/ =~ docid }
    end

    def docref_by_id(docid)
      @config.entry.detect { |k| k.identifier == docid } ||
        @config.entry.detect { |k| /^#{k.identifier}/ =~ docid }
    end

    private

    # @param builder [Nokogiri::XML::Builder]
    def docref_to_xml(builder) # KILL
      @disambig = Util::DisambigFiles.new
      @docref.each do |dr|
        drf = builder.docref do |b|
          b.identifier { |i| i << dr["identifier"] }
          !dr["attachment"] && !dr["sectionsplit"] && @collection &&
            d = @collection.bibdatas[Util::key dr["identifier"]] and
            b.parent.add_child(d.bibitem.to_xml(bibdata: true))
          m = dr["manifest"] and m.to_xml b
        end
        docref_to_xml_attrs(drf, dr)
      end
    end

    def docref_to_xml_attrs(elem, docref) # KILL
      # f = docref["fileref"] and elem[:fileref] = @disambig.strip_root(f)
      %i(attachment sectionsplit url fileref_original).each do |i|
        elem[i] = docref[i.to_s] if docref[i.to_s]
      end
      elem[:index] = docref.has_key?("index") ? docref["index"] : "true"
      elem[:presentationxml] = "true" if docref["presentation-xml"] &&
        [true, "true"].include?(docref["presentation-xml"])
      docref_to_xml_attrs_id(elem, docref)
    end

    def docref_to_xml_attrs_id(elem, docref) # KILL
      if collection&.directives&.include?("documents-inline")
        id = collection.documents.find_index do |k, _|
          k == docref["identifier"]
        end
        id and elem[:id] = format("doc%<index>09d", index: id)
      end
    end
  end
end
