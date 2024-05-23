module Metanorma
  module CollectionConstructModel
    # @param Block [Proc]
    # @note allow user-specific function to run in pre-parse model stage
    def set_pre_parse_model(&block)
      @pre_parse_model_proc = block
    end

    # @param Block [Proc]
    # @note allow user-specific function to resolve identifier
    def set_identifier_resolver(&block)
      @identifier_resolver = block
    end

    # @param Block [Proc]
    # @note allow user-specific function to resolve fileref
    # NOTE: MUST ALWAYS RETURN PATH relative to working directory
    # (initial YAML file location). @fileref_resolver.call(ref_folder, fileref)
    # fileref is not what is in the YAML, but the resolved path
    # relative to the working directory
    def set_fileref_resolver(&block)
      @fileref_resolver = block
    end

    def unset_fileref_resolver
      @fileref_resolver = nil
    end

    # @param collection_model [Hash{String=>String}]
    def pre_parse_model(collection_model)
      return unless @pre_parse_model_proc

      @pre_parse_model_proc.call(collection_model)
    end

    # @param identifier [String]
    # @return [String]
    def resolve_identifier(identifier)
      return identifier unless @identifier_resolver

      @identifier_resolver.call(identifier)
    end

    # @param fileref [String]
    # @return [String]
    def resolve_fileref(ref_folder, fileref)
      unless @fileref_resolver
        (Pathname.new fileref).absolute? or
          fileref = File.join(ref_folder, fileref)
        return fileref
      end

      @fileref_resolver.call(ref_folder, fileref)
    end

    # @param filepath
    # @raise [FileNotFoundException]
    # THIS.... IS ONLY BEING RUN FOR TOP LEVEL YAML? REALLY?
    def check_file_existence(filepath)
      unless File.exist?(filepath)
        error_message = "#{filepath} not found!"
        Util.log("[metanorma] Error: #{error_message}", :error)
        raise FileNotFoundException.new error_message.to_s
      end
    end
  end
end
