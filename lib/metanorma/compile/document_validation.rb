# frozen_string_literal: true

module Metanorma
  class Compile
    # Flavor validation runs against the semantic model before presentation.
    class DocumentValidation
      Result = Struct.new(:report, :schema_errors, :fatal_messages,
                          keyword_init: true) do
        def valid?
          schema_errors.empty? && report.valid? && fatal_messages.empty?
        end
      end

      def call(root, flavor:, options:)
        require "metanorma-iso"
        require "metanorma/iso/document"
        require "metanorma/iso/validation"
        unless flavor.to_sym == :iso && root.is_a?(Metanorma::Iso::Document::Root) &&
            root.type == "semantic"
          raise DocumentPipeline::UnavailableStageError,
                "Native validation requires the actual ISO semantic Root"
        end
        log = options.fetch(:log)
        register_messages(log)
        api = Metanorma::Iso::Validation
        state = api::StateExtractor.extract(root, document: options[:source_filename])
        state.flavor = "iso"
        registry = api::ComposedRegistry.for(flavor: "iso")
        context = api::Context.new(root: root, log: log, state: state,
                                  shared: api::SharedState.new, registry: registry)
        report = api::Report.new(document: state.document,
                                 generated_at: Time.now.utc.iso8601)
        translator = api::IssueTranslator.new(log: log, report: report)
        profile = validation_profile(options, api)
        translator.translate_layer3(registry.execute(context, profile))
        errors = schema_errors(root)
        errors.each do |message|
          log.add("STANDOC_7", "Document", params: [message])
          report.add_issue(code: "STANDOC_7", location: "Document", params: [message])
        end
        fatal = log.abort_messages.dup
        if options[:document_validation_profile] == :strict &&
            profile.fatal_findings?(report)
          fatal.concat(report.issues.select { |issue| issue.error? || issue.warning? }
            .map(&:message))
        end
        Result.new(report: report, schema_errors: errors, fatal_messages: fatal)
      end

      private

      def schema_errors(root)
        require "metanorma/validate/schema"
        schema = Object.new.extend(Metanorma::Standoc::Validate::Schema)
        schema.shared_schema_errors(root.to_xml, flavor: "iso",
                                                representation: "semantic")
      rescue Metanorma::Standoc::Validate::UniversalSchema::Error => e
        raise DocumentPipeline::UnavailableStageError,
              "Native ISO shared grammar configuration is unavailable: #{e.message}"
      end

      def register_messages(log)
        log.add_msg(Metanorma::Standoc::Converter::STANDOC_LOG_MESSAGES)
        log.add_msg(Metanorma::Iso::Converter::ISO_LOG_MESSAGES)
      end

      def validation_profile(options, api)
        case options.fetch(:document_validation_profile, :default)
        when :default then api::Profile::DEFAULT
        when :strict then api::Profile::STRICT
        else
          raise ArgumentError, "Native document validation profile must be default or strict"
        end
      end
    end
  end
end
