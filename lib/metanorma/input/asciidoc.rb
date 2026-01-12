require "nokogiri"

module Metanorma
  module Input
    class Asciidoc < Base
      def process(file, filename, type, options = {})
        require "asciidoctor"
        out_opts = { to_file: false, safe: :safe, backend: type,
                     header_footer: true, log: options[:log],
                     novalid: options[:novalid],
                     attributes: ["nodoc", "stem", "docfile=#{filename}",
                                  "output_dir=#{options[:output_dir]}"] }
        ::Asciidoctor.convert(file, out_opts)
      end

      def header(file)
        require "debug"; binding.b
        ret = file.split("\n\n", 2) or return [nil, nil]
        ret[0] and ret[0] += "\n"
        [ret[0], ret[1]]
      end

      def extract_metanorma_options(file)
        hdr, = header(file)
        /\n:(?:mn-)?(?:document-class|flavor):\s+(?<type>\S[^\n]*)\n/ =~ hdr
        /\n:(?:mn-)?output-extensions:\s+(?<extensions>\S[^\n]*)\n/ =~ hdr
        /\n:(?:mn-)?relaton-output-file:\s+(?<relaton>\S[^\n]*)\n/ =~ hdr
        /\n(?<asciimath>:(?:mn-)?keep-asciimath:[^\n]*)\n/ =~ hdr
        /\n(?<novalid>:novalid:[^\n]*)\n/ =~ hdr
        if defined?(asciimath)
          asciimath =
            !asciimath.nil? && !/keep-asciimath:\s*false/.match?(asciimath)
        end
        asciimath = nil if asciimath == false
        {
          type: defined?(type) ? type&.strip : nil,
          extensions: defined?(extensions) ? extensions&.strip : nil,
          relaton: defined?(relaton) ? relaton&.strip : nil,
          asciimath: asciimath, novalid: !novalid.nil? || nil
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
           pdf-stylesheet pdf-stylesheet-override relaton-render-config
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
        name.delete("-").sub(/override$/, "_override").sub(/pdf$/, "_pdf")
          .to_sym
      end

      def extract_options(file)
        hdr, = header(file)
        ret = ADOC_OPTIONS.each_with_object({}) do |w, acc|
          m = /\n:#{w}:\s+([^\n]+)\n/.match(hdr) or next
          acc[attr_name_normalise(w)] = m[1]&.strip
        end
        ret2 = EMPTY_ADOC_OPTIONS_DEFAULT_TRUE.each_with_object({}) do |w, acc|
          m = /\n:#{w}:([^\n]*)\n/.match(hdr) || [nil, "true"]
          acc[attr_name_normalise(w)] = (m[1].strip != "false")
        end
        ret3 = EMPTY_ADOC_OPTIONS_DEFAULT_FALSE.each_with_object({}) do |w, acc|
          m = /\n:#{w}:([^\n]*)\n/.match(hdr) || [nil, "false"]
          acc[attr_name_normalise(w)] = !["false"].include?(m[1].strip)
        end
        ret.merge(ret2).merge(ret3).compact
      end
    end
  end
end
