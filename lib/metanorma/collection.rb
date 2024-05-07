# frozen_string_literal: true

require "relaton"
require "relaton/cli"
require "metanorma/collection_manifest"
require "metanorma-utils"
require_relative "util"

module Metanorma
  class FileNotFoundException < StandardError; end

  class AdocFileNotFoundException < StandardError; end

  # Metanorma collection of documents
  class Collection
    attr_reader :file

    # @return [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    attr_accessor :directives, :documents, :bibdatas, :coverpage, :dirname
    attr_accessor :disambig, :manifest

    # @param file [String] path to source file
    # @param dirname [String] directory of source file
    # @param directives [Array<String>] documents-inline to inject the XML into
    #   the collection manifest; documents-external to keeps them outside
    # @param bibdata [RelatonBib::BibliographicItem]
    # @param manifest [Metanorma::CollectionManifest]
    # @param documents [Hash<String, Metanorma::Document>]
    # @param prefatory [String]
    # @param coverpage [String]
    # @param final [String]
    # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    def initialize(**args)
      @file = args[:file]
      @dirname = File.dirname(@file)
      @directives = args[:directives] || []
      @bibdata = args[:bibdata]
      @manifest = args[:manifest]
      @manifest.collection = self
      @coverpage = Util::hash_key_detect(@directives, "coverpage", @coverpage)
      @coverpage_style = Util::hash_key_detect(@directives, "coverpage-style",
                                               @coverpage_style)
      @documents = args[:documents] || {}
      @bibdatas = args[:documents] || {}
      if (@documents.any? || @manifest) &&
          (%w(documents-inline documents-external) & @directives).empty?
        @directives << "documents-inline"
      end
      @documents.merge! @manifest.documents(@dirname)
      @bibdatas.merge! @manifest.documents(@dirname)
      @documents.transform_keys { |k| Util::key(k) }
      @bibdatas.transform_keys { |k| Util::key(k) }
      @prefatory = args[:prefatory]
      @final = args[:final]
      @compile = Metanorma::Compile.new
      @log = Metanorma::Utils::Log.new
      @disambig = Util::DisambigFiles.new
    end

    # rubocop:enable Metrics/AbcSize,Metrics/MethodLength
    def clean_exit
      @log.write(File.join(@dirname,
                           "#{File.basename(@file, '.*')}.err.html"))
    end

    # @return [String] XML
    def to_xml
      b = Nokogiri::XML::Builder.new do |xml|
        xml.send(:"metanorma-collection",
                 "xmlns" => "http://metanorma.org") do |mc|
          collection_body(mc)
        end
      end
      b.to_xml
    end

    def collection_body(coll)
      coll << @bibdata.to_xml(bibdata: true, date_format: :full)
      @directives.each do |d|
        coll << "<directives>#{obj_to_xml(d)}</directives>"
      end
      @manifest.to_xml coll
      content_to_xml "prefatory", coll
      doccontainer coll
      content_to_xml "final", coll
    end

    def obj_to_xml(elem)
      case elem
      when ::Array
        elem.each_with_object([]) do |v, m|
          m << "<value>#{obj_to_xml(v)}</value>"
        end.join
      when ::Hash
        elem.each_with_object([]) do |(k, v), m|
          m << "<#{k}>#{obj_to_xml(v)}</#{k}>"
        end.join
      else elem end
    end

    def render(opts)
      CollectionRenderer.render self, opts.merge(log: @log)
      clean_exit
    end

    class << self
      # @param file [String]
      # @return [RelatonBib::BibliographicItem,
      #   RelatonIso::IsoBibliographicItem]
      def parse(file)
        case file
        when /\.xml$/ then parse_xml(file)
        when /.ya?ml$/ then parse_yaml(file)
        end
      end

      # @param file [String]
      # @param collection_model [Hash]
      # @return [Metanorma::Collection]
      def parse_model(file, collection_model)
        if collection_model["bibdata"]
          bd = Relaton::Cli::YAMLConvertor
            .convert_single_file(collection_model["bibdata"])
        end

        mnf  = CollectionManifest.from_yaml collection_model["manifest"]
        dirs = collection_model["directives"]
        pref = collection_model["prefatory-content"]
        fnl  = collection_model["final-content"]

        new(file: file, directives: dirs, bibdata: bd, manifest: mnf,
            prefatory: pref, final: fnl)
      end

      # @param Block [Proc]
      # @note allow user-specific function to run in pre-parse model stage
      def set_pre_parse_model(&block)
        @pre_parse_model_proc = block
      end

      # @param Block [Proc]
      # @note allow user-specific function to resolve indentifier
      def set_indentifier_resolver(&block)
        @indentifier_resolver = block
      end

      # @param Block [Proc]
      # @note allow user-specific function to resolve fileref
      def set_fileref_resolver(&block)
        @fileref_resolver = block
      end

      private

      # @param collection_model [Hash{String=>String}]
      def compile_adoc_documents(collection_model)
        documents = select_documents(collection_model)
        return unless documents

        documents["docref"]
          .select { |k, _v| File.extname(k["fileref"]) == ".adoc" }
          .each do |dr|
          compile_adoc_file(dr["fileref"])
          dr["fileref"] = set_adoc2xml(dr["fileref"])
        end
      end

      # @param collection_model [Hash{String=>String}]
      def select_documents(collection_model)
        collection_model["manifest"]["manifest"]
          .select { |k, _v| k["level"] == "document" }.first
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

        Metanorma::Compile.new.compile(filepath,
                                       agree_to_terms: true,
                                       no_install_fonts: true)

        Util.log("[metanorma] Info: Compiling #{filepath}...done!", :info)
      end

      # @param collection_model [Hash{String=>String}]
      def pre_parse_model(collection_model)
        return unless @pre_parse_model_proc

        @pre_parse_model_proc.call(collection_model)
      end

      # @param identifier [String]
      # @return [String]
      def resolve_indentifier(identifier)
        return identifier unless @indentifier_resolver

        @indentifier_resolver.call(identifier)
      end

      # @param fileref [String]
      # @return [String]
      def resolve_fileref(ref_folder, fileref)
        return fileref unless @fileref_resolver

        @fileref_resolver.call(ref_folder, fileref)
      end

      # @param collection_model [Hash{String=>String}]
      # @return [Hash{String=>String}]
      def construct_collection_manifest(collection_model)
        mnf = collection_model["manifest"]

        mnf["docref"].each do |dr|
          check_file_existance(dr["file"])
          set_default_manifest(mnf)
          construct_docref(mnf, dr)
        end

        # remove keys in upper level
        mnf.delete("docref")
        mnf.delete("sectionsplit")

        collection_model
      end

      # @param filepath
      # @raise [FileNotFoundException]
      def check_file_existance(filepath)
        unless File.exist?(filepath)
          error_message = "#{filepath} not found!"
          Util.log(
            "[metanorma] Error: #{error_message}", :error
          )
          raise FileNotFoundException.new error_message.to_s
        end
      end

      # @param manifest [Hash{String=>String}]
      def set_default_manifest(manifest)
        manifest["manifest"] ||= [
          {
            "level" => "document",
            "title" => "Document",
            "docref" => [],
          },
          {
            "level" => "attachments",
            "title" => "Attachments",
            "docref" => [],
          },
        ]
      end

      # @param collection_model [Hash{String=>String}]
      # @return [Bool]
      def new_yaml_format?(collection_model)
        mnf = collection_model["manifest"]
        # return if collection yaml is not the new format
        if mnf["docref"].nil? || mnf["docref"].empty? ||
            !mnf["docref"].first.has_key?("file")
          return false
        end

        true
      end

      # @param mnf [Hash{String=>String}]
      # @param docref [Hash{String=>String}]
      def construct_docref(mnf, docref)
        ref_folder = File.dirname(docref["file"])
        identifier = resolve_indentifier(ref_folder)
        doc_col    = YAML.load_file docref["file"]

        docref_from_document_and_attaments(doc_col).each do |m|
          m["docref"].each do |doc_dr|
            resolved_fileref = resolve_fileref(ref_folder, doc_dr["fileref"])
            append_docref(resolved_fileref, identifier, mnf, doc_dr, m["level"])
          end
        end
      end

      # @param doc_col [Hash{String=>String}]
      def docref_from_document_and_attaments(doc_col)
        doc_col["manifest"]["manifest"].select do |m|
          m["level"] == "document" || m["level"] == "attachments"
        end
      end

      # @param fileref [String]
      # @param identifier [String]
      # @param mnf [Hash{String=>String}]
      # @param doc_dr [Hash{String=>String}]
      # @param level [String]
      def append_docref(fileref, identifier, mnf, doc_dr, level)
        dr_arr = mnf["manifest"].select { |i| i["level"] == level }
        doc_ref_hash = set_doc_ref_hash(
          doc_dr["attachment"],
          fileref,
          doc_dr["identifier"] || identifier,
          doc_dr["sectionsplit"] || mnf["sectionsplit"],
        )
        dr_arr.first["docref"].append(doc_ref_hash)
      end

      # @param is_attachment [String]
      # @param fileref [String]
      # @param identifier [String]
      # @param sectionsplit [Bool]
      def set_doc_ref_hash(is_attachment, fileref, identifier, sectionsplit)
        doc_ref_hash = {
          "fileref" => fileref,
          "identifier" => identifier,
          "sectionsplit" => sectionsplit,
        }

        if is_attachment
          doc_ref_hash["attachment"] = is_attachment
          doc_ref_hash.delete("sectionsplit")
        end

        doc_ref_hash
      end

      def parse_xml(file)
        xml = Nokogiri::XML(File.read(file, encoding: "UTF-8"), &:huge)
        (b = xml.at("/xmlns:metanorma-collection/xmlns:bibdata")) and
          bd = Relaton::Cli.parse_xml(b)
        mnf_xml = xml.at("/xmlns:metanorma-collection/xmlns:manifest")
        mnf = CollectionManifest.from_xml mnf_xml
        pref = pref_final_content xml.at("//xmlns:prefatory-content")
        fnl = pref_final_content xml.at("//xmlns:final-content")
        cov = pref_final_content xml.at("//xmlns:coverpage")
        new(file: file, bibdata: bd, manifest: mnf,
            directives: directives_from_xml(xml.xpath("//xmlns:directives")),
            documents: docs_from_xml(xml, mnf),
            bibdatas: docs_from_xml(xml, mnf),
            prefatory: pref, final: fnl, coverpage: cov)
      end

      # TODO refine
      def directives_from_xml(dir)
        dir.each_with_object([]) do |d, m|
          m << if d.at("./xmlns:value")
                 x.xpath("./xmlns:value").map(&:text)
               elsif d.at("./*")
                 d.elements.each_with_object({}) do |e, ret|
                   ret[e.name] = e.children.to_xml
                 end
               else d.children.to_xml
               end
        end
      end

      def parse_yaml(file)
        collection_model = YAML.load_file file
        if new_yaml_format?(collection_model)
          collection_model = construct_collection_manifest(collection_model)
          file = File.basename(file)
        end
        pre_parse_model(collection_model)
        if collection_model["manifest"]["manifest"]
          compile_adoc_documents(collection_model)
        end
        parse_model(file, collection_model)
      end

      # @param xml [Nokogiri::XML::Document]
      # @param mnf [Metanorma::CollectionManifest]
      # @return [Hash{String=>Metanorma::Document}]
      def docs_from_xml(xml, mnf)
        xml.xpath("//xmlns:doc-container//xmlns:bibdata")
          .each_with_object({}) do |b, m|
          bd = Relaton::Cli.parse_xml b
          docref = mnf.docref_by_id bd.docidentifier.first.id
          m[docref["identifier"]] = Document.new bd, docref["fileref"]
          m
        end
      end

      # @param xml [Nokogiri::XML::Element, nil]
      # @return [String, nil]
      def pref_final_content(xml)
        xml or return
        <<~CONT

            == #{xml.at('title')&.text}
          #{xml.at('p')&.text}
        CONT
      end
    end

    private

    # @return [String, nil]
    attr_reader :prefatory, :final

    # @return [String]
    def dummy_header
      <<~DUMMY
        = X
        A

      DUMMY
    end

    # @param elm [String] 'prefatory' or 'final'
    # @param builder [Nokogiri::XML::Builder]
    def content_to_xml(elm, builder)
      return unless (cnt = send(elm))

      @compile.load_flavor(doctype)
      out = sections(dummy_header + cnt.strip)
      builder.send("#{elm}-content") { |b| b << out }
    end

    # @param cnt [String] prefatory/final content
    # @return [String] XML
    def sections(cnt)
      c = Asciidoctor.convert(cnt, backend: doctype.to_sym, header_footer: true)
      Nokogiri::XML(c, &:huge).at("//xmlns:sections").children.to_xml
    end

    # @param builder [Nokogiri::XML::Builder]
    def doccontainer(builder)
      Array(@directives).include? "documents-inline" or return
      documents.each_with_index do |(_, d), i|
        doccontainer1(builder, d, i)
      end
    end

    def doccontainer1(builder, doc, idx)
      id = format("doc%<index>09d", index: idx)
      builder.send(:"doc-container", id: id) do |b|
        if doc.attachment
          doc.bibitem and b << doc.bibitem.root.to_xml
          b.attachment Vectory::Utils::datauri(doc.file)
        else doc.to_xml b
        end
      end
    end

    def doctype
      @doctype ||= fetch_doctype || "standoc"
    end

    def fetch_doctype
      docid = @bibdata.docidentifier.first
      docid or return
      docid.type&.downcase || docid.id&.sub(/\s.*$/, "")&.downcase
    end
  end
end
