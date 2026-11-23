# frozen_string_literal: true

module Metanorma
  class Compile
    # Native orchestration. Flavor-owned source and presentation contracts must
    # exist before a flavor can complete this leg; legacy XML is never a fallback.
    class DocumentPipeline
      class UnavailableStageError < ArgumentError; end

      Result = Struct.new(:semantic_model, :presentation_model, :outputs,
                          keyword_init: true)
      FORMATS = { html: "html", xml: "xml",
                  presentation: "presentation.xml" }.freeze
      UNSUPPORTED_OPTIONS = %i[sectionsplit extract relaton site_generate
                               filename_template passthrough_presentation_xml].freeze

      def compile(filename, options)
        extensions = extensions(options)
        root_class = model_root(options.fetch(:type))
        semantic = source_model(filename, options, root_class)
        verify_model!(semantic, root_class, "source builder")
        presenter = options[:document_presenter] || native_presenter(options.fetch(:type))
        options[:document_labeler] ||= native_labeler(options.fetch(:type))
        unless presenter.respond_to?(:call)
          raise UnavailableStageError,
                "#{options[:type]} has no native presentation transform; " \
                "provide document_presenter with the genuine flavor API"
        end
        semantic_xml = semantic.to_xml if extensions.include?(:xml)
        presentation = presenter.call(semantic, flavor: options[:type],
                                               options: options)
        verify_model!(presentation, root_class, "presentation transform")
        unless presentation.respond_to?(:type) && presentation.type == "presentation"
          raise UnavailableStageError,
                "Native presentation transform must return a presentation model"
        end
        outputs = render_outputs(presentation, semantic_xml, extensions, options)
        paths = write_outputs(filename, outputs, options)
        Result.new(semantic_model: semantic, presentation_model: presentation,
                   outputs: paths)
      end

      private

      def extensions(options)
        unsupported = UNSUPPORTED_OPTIONS.select { |name| options[name] }
        unless unsupported.empty?
          raise ArgumentError,
                "Native compile does not support: #{unsupported.join(', ')}"
        end
        formats = options[:extension_keys] || [:html]
        unknown = formats - FORMATS.keys
        unless unknown.empty?
          raise ArgumentError,
                "Native compile output formats are unavailable: #{unknown.join(', ')}"
        end
        formats
      end

      def model_root(flavor)
        require "metanorma/document"
        base = Metanorma::Core::FlavorLoader.taste2flavor(flavor)
        require "metanorma/#{base}/document"
        root = Metanorma::Core::Flavors.table.canonical(flavor)&.model_root_class
        return root if root

        raise UnavailableStageError, "No native document model registered for #{flavor}"
      end

      def native_presenter(flavor)
        return nil unless Metanorma::Core::FlavorLoader.taste2flavor(flavor) == :iso

        require "metanorma/iso/presentation/transformer"
        Metanorma::Iso::Presentation::Transformer.new
      rescue LoadError => error
        raise UnavailableStageError,
              "Native ISO presentation provider is unavailable: #{error.message}"
      end

      def native_labeler(flavor)
        return nil unless Metanorma::Core::FlavorLoader.taste2flavor(flavor) == :iso

        require "metanorma/ladl"
        require "metanorma/ladl/document_adapter"
        engine = Metanorma::Ladl::Engine.new(profile: Metanorma::Ladl::Profile.iso_iec)
        lambda do |model, flavor:, options:|
          engine.call(model, adapter: Metanorma::Ladl::DocumentAdapter.new(mode: :presentation))
        end
      end

      def source_model(filename, options, root_class)
        require "coridoc/metanorma"
        Coridoc::Metanorma::Builder.parse(
          File.read(filename, encoding: "UTF-8"), format: options.fetch(:format),
                                                root_class: root_class
        )
      end

      def verify_model!(model, root_class, stage)
        return if model.is_a?(root_class)

        raise UnavailableStageError,
              "Native #{stage} returned #{model.class}; expected #{root_class}. " \
              "A direct typed flavor adapter is required; XML casting is unsupported"
      end

      def render_outputs(presentation, semantic_xml, formats, options)
        formats.to_h do |format|
          content = case format
                    when :xml then semantic_xml
                    when :presentation then presentation.to_xml
                    when :html then render_html(presentation, options)
                    end
          [format, content]
        end
      end

      def render_html(model, options)
        renderer = Metanorma::Core::Flavors.renderer_for(
          model, format: :html, flavor: options.fetch(:type)
        )
        unless renderer
          raise UnavailableStageError,
                "No native HTML renderer registered for #{options[:type]} and #{model.class}"
        end
        render_options = options.reject { |key, _value| %i[pipeline document_presenter document_labeler].include?(key) }
        renderer.new.generate_full_document(model, **render_options)
      end

      def write_outputs(filename, contents, options)
        names = OutputFilename.from_filename(filename, options[:output_dir])
        contents.to_h do |format, content|
          path = names.with_extension(FORMATS.fetch(format))
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content, encoding: "UTF-8")
          [format, path]
        end
      end
    end

    def compile_document(filename, options)
      require_libraries(options)
      options[:type] = options[:type]&.to_sym
      raise ArgumentError, "Native compile requires an explicit type" unless options[:type]

      options[:format] ||= File.extname(filename).downcase == ".md" ? :markdown : :asciidoc
      unless %i[asciidoc markdown].include?(options[:format])
        raise ArgumentError, "Native compile source format must be asciidoc or markdown"
      end
      @log.save_to(filename, options[:output_dir])
      options[:log] = @log
      DocumentPipeline.new.compile(filename, options)
    end

    def compile_pipeline(options)
      pipeline = options.fetch(:pipeline, :legacy)
      pipeline = pipeline.to_sym if pipeline.is_a?(String)
      return pipeline if %i[legacy document].include?(pipeline)

      raise ArgumentError, "Unknown compile pipeline #{pipeline.inspect}; expected legacy or document"
    end
  end
end
