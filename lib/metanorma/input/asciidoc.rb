require "nokogiri"

module Metanorma
  module Input
    class Asciidoc < Base
      def process(file, filename, type, options = {})
        require "asciidoctor"
        out_opts = {
          to_file: false, safe: :safe, backend: type, header_footer: true,
          attributes: ["nodoc", "stem", "docfile=#{filename}",
                       "output_dir=#{options[:output_dir]}"]
        }
        unless asciidoctor_validate(file, filename, out_opts)
          warn "Cannot continue compiling Asciidoctor document"
          abort
        end
        ::Asciidoctor.convert(file, out_opts)
      end

      def asciidoctor_validate(file, filename, options)
        err = nil
        begin
          previous_stderr = $stderr
          $stderr = StringIO.new
          ::Asciidoctor.load(file, options)
          %r{(\n|^)asciidoctor: ERROR: ['"]?#{Regexp.escape(filename ||
            "<empty>")}['"]?: line \d+: include file not found: }
            .match($stderr.string) and err = $stderr.string
        ensure
          $stderr = previous_stderr
        end
        warn err unless err.nil?
        err.nil?
      end

      def extract_metanorma_options(file)
        headerextract = file.sub(/\n\n.*$/m, "\n")
        /\n:mn-document-class:\s+(?<type>[^\n]+)\n/ =~ headerextract
        /\n:mn-output-extensions:\s+(?<extensions>[^\n]+)\n/ =~ headerextract
        /\n:mn-relaton-output-file:\s+(?<relaton>[^\n]+)\n/ =~ headerextract
        /\n(?<asciimath>:mn-keep-asciimath:[^\n]*)\n/ =~ headerextract
        asciimath = if defined?(asciimath)
                      (!asciimath.nil? && asciimath != ":mn-keep-asciimath: false")
                    end
        asciimath = nil if asciimath == false
        {
          type: defined?(type) ? type&.strip : nil,
          extensions: defined?(extensions) ? extensions&.strip : nil,
          relaton: defined?(relaton) ? relaton&.strip : nil,
          asciimath: asciimath,
        }.compact
      end

      def empty_attr(attr, name)
        attr&.sub(/^#{name}:\s*$/, "#{name}: true")&.sub(/^#{name}:\s+/, "")
      end

      ADOC_OPTIONS =
        %w(htmlstylesheet htmlcoverpage htmlintropage scripts
           scripts-override scripts-pdf wordstylesheet i18nyaml
           standardstylesheet header wordcoverpage wordintropage
           ulstyle olstyle htmlstylesheet-override bare toclevels
           htmltoclevels doctoclevels sectionsplit base-asset-path
           body-font header-font monospace-font title-font
           align-cross-elements wordstylesheet-override ieee-dtd
           pdf-encrypt pdf-encryption-length pdf-user-password
           pdf-owner-password pdf-allow-copy-content pdf-allow-edit-content
           pdf-allow-assemble-document pdf-allow-edit-annotations
           pdf-allow-print pdf-allow-print-hq pdf-allow-fill-in-forms
           fonts font-license-agreement pdf-allow-access-content
           pdf-encrypt-metadata iso-word-template document-scheme
           localize-number iso-word-bg-strip-color modspec-identifier-base)
          .freeze

      EMPTY_ADOC_OPTIONS_DEFAULT_TRUE =
        %w(data-uri-image suppress-asciimath-dup use-xinclude
           source-highlighter).freeze

      EMPTY_ADOC_OPTIONS_DEFAULT_FALSE =
        %w(hierarchical-assets break-up-urls-in-tables toc-figures
           toc-tables toc-recommendations).freeze

      def attr_name_normalise(name)
        name.gsub("-", "").sub(/override$/, "_override").sub(/pdf$/, "_pdf")
          .to_sym
      end

      def extract_options(file)
        header = file.sub(/\n\n.*$/m, "\n")
        ret = ADOC_OPTIONS.each_with_object({}) do |w, acc|
          m = /\n:#{w}:\s+([^\n]+)\n/.match(header) or next
          acc[attr_name_normalise(w)] = m[1]&.strip
        end
        ret2 = EMPTY_ADOC_OPTIONS_DEFAULT_TRUE.each_with_object({}) do |w, acc|
          m = /\n:#{w}:([^\n]*)\n/.match(header) || [nil, "true"]
          acc[attr_name_normalise(w)] = (m[1].strip != "false")
        end
        ret3 = EMPTY_ADOC_OPTIONS_DEFAULT_FALSE.each_with_object({}) do |w, acc|
          m = /\n:#{w}:([^\n]*)\n/.match(header) || [nil, "false"]
          acc[attr_name_normalise(w)] = !["false"].include?(m[1].strip)
        end
        ret.merge(ret2).merge(ret3).compact
      end
    end
  end
end
