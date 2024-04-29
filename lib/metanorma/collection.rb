# frozen_string_literal: true

require "relaton"
require "relaton/cli"
require "metanorma/collection_manifest"
require "metanorma-utils"
require_relative "util"

module Metanorma
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
        collection_model = construct_collection_manifest(collection_model)

        # run user-specific proc before parse model
        pre_parse_model(collection_model)

        # compile adoc documents
        compile_adoc_documents(collection_model)

        if collection_model["bibdata"]
          bd = Relaton::Cli::YAMLConvertor.convert_single_file(
            collection_model["bibdata"]
          )
        end

        mnf  = CollectionManifest.from_yaml collection_model["manifest"]
        dirs = collection_model["directives"]
        pref = collection_model["prefatory-content"]
        fnl  = collection_model["final-content"]

        new(
          file: file,
          directives: dirs,
          bibdata: bd,
          manifest: mnf,
          prefatory: pref,
          final: fnl,
        )
      end

      # @parma Block [Proc]
      # @note allow user-specific function to run in pre-parse model stage
      def set_pre_parse_model(&block)
        @pre_parse_model_proc = block
      end

      # @parma Block [Proc]
      # @note allow user-specific function to resolve indentifier
      def set_indentifier_resolver(&block)
        @indentifier_resolver = block
      end

      # @parma Block [Proc]
      # @note allow user-specific function to resolve fileref
      def set_fileref_resolver(&block)
        @fileref_resolver = block
      end

      private

      # @parma collection_model [Hash{String=>String}]
      def compile_adoc_documents(collection_model)
        mnf = collection_model["manifest"]["manifest"]
        return unless mnf

        mnf.each do |doc|
          if doc['level'] == 'document'
            doc['docref'].each do |dr|
              fileref  = dr['fileref']

              Util.log(
                "[metanorma] Error: #{fileref} not found!", :error
              ) unless File.exist?(fileref)

              if File.extname(fileref) == ".adoc"
                Util.log(
                  "[metanorma] Info: Compiling #{fileref}...", :info
                )
                Metanorma::Compile.new.compile(
                  fileref,
                  agree_to_terms: true,
                  no_install_fonts: true
                )
                Util.log(
                  "[metanorma] Info: Compiling #{fileref}...done!", :info
                )
              end

              # set fileref to xml file after compilation
              dr['fileref'] = "#{File.dirname(fileref)}/#{File.basename(
                                fileref,
                                File.extname(fileref)
                              )}.xml"
            end
          end
        end
      end

      # @parma collection_model [Hash{String=>String}]
      def pre_parse_model(collection_model)
        return unless @pre_parse_model_proc
        @pre_parse_model_proc.call(collection_model)
      end

      # @parma identifier [String]
      # @return [String]
      def resolve_indentifier(identifier)
        return identifier unless @indentifier_resolver
        @indentifier_resolver.call(identifier)
      end

      # @parma fileref [String]
      # @return [String]
      def resolve_fileref(ref_folder, fileref)
        return fileref unless @fileref_resolver
        @fileref_resolver.call(ref_folder, fileref)
      end

      # @parma collection_model [Hash{String=>String}]
      # @return [Hash{String=>String}]
      def construct_collection_manifest(collection_model)
        mnf = collection_model["manifest"]

        # return if collection yaml is not the new format
        if mnf["docref"].nil? || mnf["docref"].empty? ||
           !mnf["docref"].first.has_key?('file')

          return collection_model
        end

        mnf["docref"].each do |dr|
          # check file existance
          unless File.exist?(dr['file'])
            Util.log(
              "[metanorma] Error: #{dr['file']} not found!", :error
            )
          end

          # set default manifest
          mnf["manifest"] ||= [
            {
              "level"  => "document",
              "title"  => "Document",
              "docref" => []
            },
            {
              "level"  => "attachments",
              "title"  => "Attachments",
              "docref" => []
            }
          ]

          ref_folder = File.dirname(dr['file'])
          identifier = resolve_indentifier(ref_folder)
          doc_col    = YAML.load_file dr['file']

          # append documents or attachments into docref[] of manifest
          doc_col['manifest']['manifest'].each do |m|
            m['docref'].each do |doc_dr|
              resolved_fileref = resolve_fileref(
                                    ref_folder,
                                    doc_dr['fileref']
                                  )

              case m['level']
              when 'document', 'attachments'
                dr_arr = mnf["manifest"].select do |i|
                  i['level'] == m['level']
                end

                doc_ref_hash = {
                                  "fileref"      => resolved_fileref,
                                  "identifier"   => doc_dr['identifier'] ||
                                                    identifier,
                                  "sectionsplit" => doc_dr['sectionsplit'] ||
                                                    mnf['sectionsplit'],
                                }

                if doc_dr['attachment']
                  doc_ref_hash.merge!({"attachment" => doc_dr['attachment']})
                  doc_ref_hash.delete('sectionsplit')
                end

                dr_arr.first['docref'].append(doc_ref_hash)
              end
            end
          end
        end

        # remove keys in upper level
        mnf.delete("docref")
        mnf.delete("sectionsplit")

        return collection_model
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
        yaml = YAML.load_file file
        parse_model(file, yaml)
      end

      # @param xml [Nokogiri::XML::Document]
      # @parma mnf [Metanorma::CollectionManifest]
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
