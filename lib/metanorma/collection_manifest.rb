# frozen_string_literal: true

require_relative "util"

module Metanorma
  # Metanorma collection's manifest
  class CollectionManifest
    # @return [Metanorma::Collection]
    attr_reader :collection

    # @param level [String]
    # @param title [String, nil]
    # @param docref [Array<Hash{String=>String}>]
    # @param manifest [Array<Metanorma::CollectionManifest>]
    def initialize(level, title = nil, docref = [], manifest = [])
      @level = level
      @title = title
      @docref = docref
      @manifest = manifest
      @disambig = Util::DisambigFiles.new
    end

    class << self
      # @param mnf [Nokogiri::XML::Element]
      # @return [Metanorma::CollectionManifest]
      def from_yaml(mnf)
        manifest = RelatonBib::HashConverter.array(mnf["manifest"]).map do |m|
          from_yaml m
        end
        docref = RelatonBib::HashConverter.array mnf["docref"]
        new(mnf["level"], mnf["title"], docref, manifest)
      end

      # @param mnf [Nokogiri::XML::Element]
      # @return [Metanorma::CollectionManifest]
      def from_xml(mnf)
        level = mnf.at("level").text
        title = mnf.at("title")&.text
        manifest = mnf.xpath("xmlns:manifest").map { |m| from_xml(m) }
        new(level, title, parse_docref(mnf), manifest)
      end

      private

      # @param mnf [Nokogiri::XML::Element]
      # @return [Hash{String=>String}]
      def parse_docref(mnf)
        mnf.xpath("xmlns:docref").map do |dr|
          h = { "identifier" => dr.at("identifier").children.to_xml }
          %i(fileref attachment sectionsplit index).each do |s|
            h[s.to_s] = dr[s] if dr[s]
          end
          h["presentation-xml"] = dr[:presentationxml] if dr[:presentationxml]
          h
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
        next m unless dr["fileref"]

        m[dr["identifier"]] = Document.parse_file(
          File.join(dir, dr["fileref"]),
          dr["attachment"], dr["identifier"], dr["index"]
        )
        m
      end
      @manifest.reduce(docs) { |mem, mnf| mem.merge mnf.documents(dir) }
    end

    # @param builder [Nokogiri::XML::Builder]
    def to_xml(builder)
      builder.manifest do |b|
        b.level @level
        b.title @title if @title
        docref_to_xml b
        @manifest.each { |m| m.to_xml b }
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
      dref || docrefs.detect { |k| /^#{k["identifier"]}/ =~ docid }
    end

    private

    # @param builder [Nokogiri::XML::Builder]
    def docref_to_xml(builder)
      @disambig = Util::DisambigFiles.new
      @docref.each do |dr|
        drf = builder.docref do |b|
          b.identifier do |i|
            i << dr["identifier"]
          end
        end
        docref_to_xml_attrs(drf, dr)
      end
    end

    def docref_to_xml_attrs(elem, docref)
      elem[:fileref] = @disambig.source2dest_filename(docref["fileref"])
      %i(attachment sectionsplit).each do |i|
        elem[i] = docref[i.to_s] if docref[i.to_s]
      end
      elem[:index] = docref.has_key?("index") ? docref["index"] : "true"
      elem[:presentationxml] = "true" if docref["presentation-xml"] &&
        [true, "true"].include?(docref["presentation-xml"])
      docref_to_xml_attrs_id(elem, docref)
    end

    def docref_to_xml_attrs_id(elem, docref)
      if collection.directives.include?("documents-inline")
        id = collection.documents.find_index do |k, _|
          k == docref["identifier"]
        end
        elem[:id] = format("doc%<index>09d", index: id)
      end
    end
  end
end
