require "fontist"
module Metanorma
  module Util
    class FontistHelper
      class << self
        private

        def validate_options(options)
          agree_to_terms = options[:agree_to_terms] || false
          continue_without_fonts = options[:continue_without_fonts] || false
          no_progress = !options[:progress]

          [agree_to_terms, continue_without_fonts, no_progress]
        end

        def validate_install_fonts(processor, options)
          unless install_fonts?(options)
            Util.log("[fontist] Skip font installation because" \
                     " --no-install-fonts argument passed", :debug)
            return false
          end
          unless has_custom_fonts?(processor, options, options)
            Util.log("[fontist] Skip font installation because "\
                     "fonts_manifest is missing", :debug)
            return false
          end
          true
        end

        def install_fonts_safe(manifest, agree, continue, no_progress)
          fontist_install(manifest, agree, no_progress)
        rescue Fontist::Errors::LicensingError
          license_error_log(continue)
        rescue Fontist::Errors::FontError => e
          log_level = continue ? :warning : :fatal
          Util.log("[fontist] '#{e.font}' font is not supported. " \
                   "Please report this issue at " \
                   "github.com/metanorma/metanorma/issues", log_level)
        rescue Fontist::Errors::FormulaIndexNotFoundError
          fontist_update_repo(manifest, agree, continue, no_progress)
        end

        def fontist_install(manifest, agree, no_progress)
          if agree
            no_license_log
          else
            Fontist.log_level = :info
          end

          Fontist::Manifest::Install.from_hash(
            manifest,
            confirmation: agree ? "yes" : "no",
            no_progress: no_progress,
          )
        end

        def license_error_log(continue)
          if continue
            Util.log(
              "[fontist] Processing will continue without fonts installed",
              :debug,
            )
          else
            Util.log("[fontist] Aborting without proper fonts installed," \
                     " make sure that you have set option --agree-to-terms",
                     :fatal)
          end
        end

        def no_license_log
          Util.log(
            "[fontist] Font licenses are not shown with --agree-to-terms option.",
            :info,
          )
        end

        def fontist_update_repo(manifest, agree, continue, no_progress)
          if @@updated_formulas_repo
            Util.log(
              "[fontist] Bug: formula index not found after 'fontist update'",
              :fatal,
            )
          end
          Util.log("[fontist] Missing formula index. Fetching it...", :debug)
          Fontist::Formula.update_formulas_repo
          @@updated_formulas_repo = true
          install_fonts_safe(manifest, agree, continue, no_progress)
        end
      end

      def self.install_fonts(processor, options)
        return unless validate_install_fonts(processor, options)

        @@updated_formulas_repo = false
        manifest = processor.fonts_manifest.dup
        append_source_fonts(manifest, options)
        agree_to_terms, can_without_fonts, no_progress = validate_options(options)

        install_fonts_safe(
          manifest,
          agree_to_terms,
          can_without_fonts,
          no_progress,
        )
      end

      def self.has_custom_fonts?(processor, options, source_attributes)
        install_fonts?(options) \
          && processor.respond_to?(:fonts_manifest) \
          && !processor.fonts_manifest.nil? \
          || source_attributes[:fonts]
      end

      def self.location_manifest(processor, source_attributes)
        Fontist::Manifest::Locations.from_hash(
          append_source_fonts(processor.fonts_manifest.dup, source_attributes),
        )
      end

      def self.append_source_fonts(manifest, source_attributes)
        source_attributes[:fonts]&.split(";")&.each { |f| manifest[f] = nil }
        manifest
      end

      def self.install_fonts?(options)
        options[:install_fonts].nil? || options[:install_fonts]
      end
    end
  end
end
