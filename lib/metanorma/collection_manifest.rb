# frozen_string_literal: true

require_relative "util"

module Metanorma
  # Metanorma collection's manifest
  class CollectionManifest
    # @return [Metanorma::Collection]
    attr_reader :collection

    # @param level [String]
    # @param dir [String]
    # @param title [String, nil]
    # @param docref [Array<Hash{String=>String}>]
    # @param manifest [Array<Metanorma::CollectionManifest>]
    def initialize(level, dir, title = nil, docref = [], manifest = [])
      @dir = dir
      @level = level
      @title = title
      @docref = docref
      @manifest = manifest
      @disambig = Util::DisambigFiles.new
    end

    class << self
      # @param mnf [Nokogiri::XML::Element]
      # @return [Metanorma::CollectionManifest]
      def from_yaml(mnf, dir)
        manifest = RelatonBib.array(mnf["manifest"]).map do |m|
          from_yaml m, dir
        end
        docref = RelatonBib.array mnf["docref"]
        new(mnf["level"], dir, mnf["title"], parse_docrefs_yaml(docref, dir), manifest)
      end

      # @param mnf [Nokogiri::XML::Element]
      # @return [Metanorma::CollectionManifest]
      def from_xml(mnf, dir)
        level = mnf.at("level").text
        title = mnf.at("title")&.text
        manifest = mnf.xpath("xmlns:manifest").map { |m| from_xml(m, dir) }
        new(level, dir, title, parse_docrefs_xml(mnf, dir), manifest)
      end

      private

      # We will deal with YAML files on sighting them,
      # before passing the manifest on to anything else
      def parse_docrefs_yaml(docrefs, dir)
        docrefs.map do |dr|
          h = {}
          h["identifier"] =
            dr["identifier"] || UUIDTools::UUID.random_create.to_s
          dr["manifest"] and h["manifest"] = from_yaml(dr["manifest"].first, dir)
          compile_adoc(dr, dir)
          %w(fileref url attachment sectionsplit index presentation-xml)
            .each do |k|
            dr.has_key?(k) and h[k] = dr[k]
          end
          h
        end
      end

      def compile_adoc(ref, dir)
        f = ref["fileref"] or return
        #(Pathname.new f).absolute? or f = File.join(dir, f)
      File.extname(f) == ".adoc" or return
      compile_adoc_file(f)
      ref["fileref"] = set_adoc2xml(ref["fileref"])
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
    def compile_adoc_file(filepath)
      unless File.exist? filepath
        raise AdocFileNotFoundException.new "#{filepath} not found!"
      end
      Util.log("[metanorma] Info: Compiling #{filepath}...", :info)
      Metanorma::Compile.new
        .compile(filepath, agree_to_terms: true, no_install_fonts: true)
      Util.log("[metanorma] Info: Compiling #{filepath}...done!", :info)
    end


      # @param mnf [Nokogiri::XML::Element]
      # @return [Hash{String=>String}]
      def parse_docrefs_xml(mnf, dir)
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

      def parse_docrefs_xml_id(docref)
        if i = docref.at("identifier")
          i.children.to_xml
        else UUIDTools::UUID.random_create
        end
      end
    end

    # @param col [Metanorma::Collection]
    def collection=(col)
      @collection = col
      @manifest.each { |mnf| mnf.collection = col }
    end

    # @param dir [String] path to collection
    # @return [Hash<String, Metanorma::Document>]
    def documents(dir = "")
      docs = @docref.each_with_object({}) do |dr, m|
        if dr["fileref"]
          m[Util::key dr["identifier"]] = documents_add(dir, dr)
        elsif dr["manifest"]
          m.merge! dr["manifest"].documents(dir)
        end
        m
      end
      @manifest.reduce(docs) { |mem, mnf| mem.merge mnf.documents(dir) }
    end

    def documents_add(dir, docref)
      Document.parse_file(
        Util::rel_path_resolve(dir, docref["fileref"]),
        docref["attachment"], docref["identifier"], docref["index"]
      )
    end

    # @param builder [Nokogiri::XML::Builder]
    def to_xml(builder)
      builder.manifest do |b|
        b.level @level
        b.title @title if @title
        docref_to_xml b
        @manifest&.each { |m| m.to_xml b }
      end
    end

    # @return [Array<Hash{String=>String}>]
    def docrefs
      return @docrefs if @docrefs

      drfs = @docref.map { |dr| dr }
      @manifest.reduce(drfs) { |mem, mnf| mem + mnf.docrefs }
    end

    def docref_by_id(docid)
      refs = docrefs
      dref = refs.detect { |k| k["identifier"] == docid }
      dref || docrefs.detect { |k| /^#{k['identifier']}/ =~ docid }
    end

    private

    # @param builder [Nokogiri::XML::Builder]
    def docref_to_xml(builder)
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

    def docref_to_xml_attrs(elem, docref)
      f = docref["fileref"] and elem[:fileref] = @disambig.strip_root(f)
      %i(attachment sectionsplit url fileref_original).each do |i|
        elem[i] = docref[i.to_s] if docref[i.to_s]
      end
      elem[:index] = docref.has_key?("index") ? docref["index"] : "true"
      elem[:presentationxml] = "true" if docref["presentation-xml"] &&
        [true, "true"].include?(docref["presentation-xml"])
      docref_to_xml_attrs_id(elem, docref)
    end

    def docref_to_xml_attrs_id(elem, docref)
      if collection&.directives&.include?("documents-inline")
        id = collection.documents.find_index do |k, _|
          k == docref["identifier"]
        end
        id and elem[:id] = format("doc%<index>09d", index: id)
      end
    end
  end
end
