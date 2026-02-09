module Metanorma
  class Compile
    # Generate presentation XML from semantic XML
    def generate_presentation_xml(source_file, xml, bibdata, output_paths, opt)
      process_ext(:presentation, source_file, xml, bibdata, output_paths, opt)
    end

    # Generate multiple output formats with parallel processing
    def generate_outputs_parallel(
      source_file, semantic_xml, bibdata, extensions, output_paths, options
    )
      @queue = ::Metanorma::Util::WorkersPool.new(
        ENV["METANORMA_PARALLEL"]&.to_i || DEFAULT_NUM_WORKERS,
      )
      # Install required fonts for all extensions
      gather_and_install_fonts(source_file, options.dup, extensions)
      # Process each extension in order
      process_extensions_in_order(
        source_file, semantic_xml, bibdata, extensions, output_paths, options
      )
      @queue.shutdown
    end

    def process_extensions_in_order(
      source_file, semantic_xml, bibdata, extensions, output_paths, options
    )
      Util.sort_extensions_execution(extensions).each do |ext|
        process_ext(
          ext, source_file, semantic_xml, bibdata, output_paths, options
        ) or break
      end
    end

    # Export given bibliographic data to Relaton XML on disk
    # @param bibdata [Nokogiri::XML::Element] the bibliographic data element
    # @param options [Hash] compilation options
    def export_relaton_from_bibdata(bibdata, options)
      options[:relaton] or return
      export_output(options[:relaton], bibdata.to_xml)
    end

    # @param xml [Nokogiri::XML::Document] the XML document
    # @return [Nokogiri::XML::Element] the bibliographic data element
    def extract_relaton_metadata(xml)
      xml.at("//bibdata") || xml.at("//xmlns:bibdata")
    end

    def wrap_html(options, file_extension, outfilename)
      if options[:wrapper] && /html$/.match(file_extension)
        outfilename = outfilename.sub(/\.html$/, "")
        FileUtils.mkdir_p outfilename
        FileUtils.mv "#{outfilename}.html", outfilename
        FileUtils.mv "#{outfilename}_images", outfilename, force: true
      end
    end

    # isodoc is Raw Metanorma XML
    def gather_and_install_fonts(source_file, options, extensions)
      Util.sort_extensions_execution(extensions).each do |ext|
        isodoc_options = get_isodoc_options(source_file, options, ext)
        font_install(isodoc_options.merge(options))
      end
    end

    # Process a single extension (output format)
    def process_ext(ext, source_file, semantic_xml, bibdata, output_paths,
                    options)
      output_paths[:ext] = @processor.output_formats[ext]
      output_paths[:out] = @output_filename.for_format(ext) ||
        output_paths[:xml].sub(/\.[^.]+$/, ".#{output_paths[:ext]}")
      isodoc_options = get_isodoc_options(source_file, options, ext)

      # Handle special cases first
      return true if process_ext_special(
        ext, semantic_xml, bibdata, output_paths, options, isodoc_options
      )

      # Otherwise, determine if it uses presentation XML
      if @processor.use_presentation_xml(ext)
        # Format requires presentation XML first, then convert to final format
        process_via_presentation_xml(ext, output_paths, options, isodoc_options)
      else
        # Format can be generated directly from semantic XML
        process_from_semantic_xml(
          ext, output_paths, semantic_xml, isodoc_options
        )
      end
    end

    # Process special extensions with custom handling
    def process_ext_special(
      ext, sem_xml, bibdata, output_paths, options, isodoc_options
    )
      if ext == :rxl
        # Special case: Relaton export
        export_relaton_from_bibdata(
          bibdata,
          options.merge(relaton: output_paths[:out]),
        )
        true
      elsif ext == :presentation && options[:passthrough_presentation_xml]
        # Special case: Pass through presentation XML
        f = if File.exist?(output_paths[:orig_filename])
              output_paths[:orig_filename]
            else
              output_paths[:xml]
            end
        FileUtils.cp f, output_paths[:presentationxml]
        true
      elsif ext == :html && options[:sectionsplit]
        # Special case: Split HTML into sections
        sectionsplit_convert(
          output_paths[:xml], sem_xml, output_paths[:out], isodoc_options
        )
        true
      else
        false
      end
    end

    # Process format that requires presentation XML
    def process_via_presentation_xml(ext, output_paths, options, isodoc_options)
      @queue.schedule(ext, output_paths.dup, options.dup,
                      isodoc_options.dup) do |a, b, c, d|
                        process_output_from_presentation_xml(a, b, c, d)
                      end
    end

    # Generate output format from presentation XML
    def process_output_from_presentation_xml(ext, output_paths, options,
                                             isodoc_options)
      @processor.output(nil, output_paths[:presentationxml],
                        output_paths[:out], ext, isodoc_options)
      wrap_html(options, output_paths[:ext], output_paths[:out])
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options[:strict] == true
      isodoc_error_process(e, strict, false)
    end

    # Process format directly from semantic XML
    def process_from_semantic_xml(ext, output_paths, sem_xml, isodoc_options)
      @processor.output(sem_xml, output_paths[:xml], output_paths[:out],
                        ext, isodoc_options)
      true # Return as Thread equivalent
    rescue StandardError => e
      strict = ext == :presentation || isodoc_options[:strict] == "true"
      isodoc_error_process(e, strict, true)
      ext != :presentation
    end

    # assume we pass in Presentation XML, but we want to recover Semantic XML
    def sectionsplit_convert(input_filename, file, output_filename = nil,
                             opts = {})
      @isodoc ||= IsoDoc::PresentationXMLConvert.new({})
      input_filename += ".xml" unless input_filename.match?(/\.xml$/)
      File.exist?(input_filename) or export_output(input_filename, file)
      presxml = File.read(input_filename, encoding: "utf-8")
      _xml, filename, dir = @isodoc.convert_init(presxml, input_filename, false)
      ::Metanorma::Collection::Sectionsplit.new(
        input: input_filename, isodoc: @isodoc, xml: presxml,
        base: File.basename(output_filename || filename),
        sectionsplit_filename: opts[:sectionsplit_filename],
        output: output_filename || filename, dir: dir, compile_opts: opts
      ).build_collection
    end

    private

    def isodoc_error_process(err, strict, must_abort)
      if strict || err.message.include?("Fatal:")
        @errors << err.message
      else
        puts err.message
      end
      puts err.backtrace.join("\n")
      must_abort and 1
    end
  end
end
