module Metanorma
  class FontistUtils
    class << self
      private

      def validate_options(options)
        agree_to_terms = options[:agree_to_terms] || false
        continue_without_fonts = options[:continue_without_fonts] || false
        no_progress = options[:no_progress] || false

        [agree_to_terms, continue_without_fonts, no_progress]
      end

      def validate_install_fonts(processor, options)
        if options[:no_install_fonts]
          Util.log("[fontist] Skip font installation because" \
                   " --no-install-fonts argument passed", :debug)
          return false
        elsif !has_fonts_manifest?(processor)
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
                 "Please report this issue at github.com/metanorma/metanorma" \
                 "/issues to report this issue.", log_level)
      rescue Fontist::Errors::FormulaIndexNotFoundError
        fintist_update_repo(manifest, agree, continue, no_progress)
      end

      def fontist_install(manifest, agree, no_progress)
        if agree
          no_license_log
        else
          Fontist.log_level = :debug
        end

        puts manifest.inspect
        result = Fontist::Manifest::Install.from_hash(
          manifest,
          confirmation: agree ? "yes" : "no",
          no_progress: no_progress,
        )

        puts result.inspect

        result
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

      def fintist_update_repo(manifest, agree, continue, no_progress)
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
      manifest = processor.fonts_manifest
      agree_to_terms, can_without_fonts, no_progress = validate_options(options)

      install_fonts_safe(
        manifest,
        agree_to_terms,
        can_without_fonts,
        no_progress,
      )
    end

    def self.has_fonts_manifest?(processor, options = {})
      !options[:no_install_fonts] \
        && processor.respond_to?(:fonts_manifest) \
        && !processor.fonts_manifest.nil?
    end

    def self.location_manifest(processor)
      Fontist::Manifest::Locations.from_hash(processor.fonts_manifest)
    end
  end
end
