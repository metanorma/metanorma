module Metanorma
  class Collection
    class << self
      DEFAULT_MANIFEST = [{ "level" => "document",
                            "title" => "Document",
                            "docref" => [] },
                          { "level" => "attachments",
                            "title" => "Attachments",
                            "docref" => [] }].freeze

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

        Metanorma::Compile.new
          .compile(filepath, agree_to_terms: true, no_install_fonts: true)

        Util.log("[metanorma] Info: Compiling #{filepath}...done!", :info)
      end

      # @param collection_model [Hash{String=>String}]
      # @return [Hash{String=>String}]
      def construct_collection_manifest(collection_model)
        mnf = collection_model["manifest"]

        mnf["docref"].each do |dr|
          check_file_existence(dr["fileref"])
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
      def check_file_existence(filepath)
        unless File.exist?(filepath)
          error_message = "#{filepath} not found!"
          Util.log("[metanorma] Error: #{error_message}", :error)
          raise FileNotFoundException.new error_message.to_s
        end
      end

      # @param manifest [Hash{String=>String}]
      def set_default_manifest(manifest)
        manifest["manifest"] ||= DEFAULT_MANIFEST
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

        docref_from_document_and_attachments(doc_col).each do |m|
          m["docref"].each do |doc_dr|
            doc_ref_hash = set_doc_ref_hash(doc_dr, ref_folder, identifier, mnf)
            append_docref(mnf, m["level"], doc_ref_hash)
          end
        end
      end

      # @param doc_col [Hash{String=>String}]
      def docref_from_document_and_attachments(doc_col)
        doc_col["manifest"]["manifest"].select do |m|
          m["level"] == "document" || m["level"] == "attachments"
        end
      end

      # @param mnf [Hash{String=>String}]
      # @param level [String]
      # @param doc_ref_hash [Hash{String=>String}]
      def append_docref(mnf, level, doc_ref_hash)
        dr_arr = mnf["manifest"].select { |i| i["level"] == level }
        dr_arr.first["docref"].append(doc_ref_hash)
      end

      # @param doc_dr [Hash{String=>String}]
      # @param ref_folder [String]
      # @param identifier [String]
      # @param mnf [Hash{String=>String}]
      def set_doc_ref_hash(doc_dr, ref_folder, identifier, mnf)
        doc_ref_hash = {
          "fileref" => resolve_fileref(ref_folder, doc_dr["fileref"]),
          "identifier" => doc_dr["identifier"] || identifier,
          "sectionsplit" => doc_dr["sectionsplit"] || mnf["sectionsplit"],
        }

        if doc_dr["attachment"]
          doc_ref_hash["attachment"] = doc_dr["attachment"]
          doc_ref_hash.delete("sectionsplit")
        end

        doc_ref_hash
      end
    end
  end
end
