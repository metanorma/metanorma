require "nokogiri"

module Metanorma
  module Input
    class Asciidoc < Base
      def process(file, filename, type, options = {})
        require "asciidoctor"
        out_opts = {
          to_file: false, safe: :safe, backend: type, header_footer: true,
          attributes: ["nodoc", "stem", "xrefstyle=short",
                       "docfile=#{filename}",
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
        /\n:mn-document-class: (?<type>[^\n]+)\n/ =~ headerextract
        /\n:mn-output-extensions: (?<extensions>[^\n]+)\n/ =~ headerextract
        /\n:mn-relaton-output-file: (?<relaton>[^\n]+)\n/ =~ headerextract
        /\n(?<asciimath>:mn-keep-asciimath:[^\n]*)\n/ =~ headerextract
        asciimath = if defined?(asciimath)
                      (!asciimath.nil? && asciimath != ":mn-keep-asciimath: false")
                    end
        asciimath = nil if asciimath == false
        {
          type: defined?(type) ? type : nil,
          extensions: defined?(extensions) ? extensions : nil,
          relaton: defined?(relaton) ? relaton : nil,
          asciimath: asciimath,
        }.reject { |_, val| val.nil? }
      end

      def empty_attr(attr, name)
        attr&.sub(/^#{name}:\s*$/, "#{name}: true")&.sub(/^#{name}:\s+/, "")
      end

      ADOC_OPTIONS = %w(htmlstylesheet htmlcoverpage htmlintropage scripts
                        scripts-override scripts-pdf wordstylesheet bare i18nyaml
                        standardstylesheet header wordcoverpage wordintropage
                        ulstyle olstyle htmlstylesheet-override
                        htmltoclevels doctoclevels sectionsplit
                        body-font header-font monospace-font title-font
                        wordstylesheet-override).freeze

      def extract_options(file)
        header = file.sub(/\n\n.*$/m, "\n")
        ret = ADOC_OPTIONS.each_with_object({}) do |w, acc|
          m = /\n:#{w}: ([^\n]+)\n/.match(header) or next
          acc[w.gsub(/-/, "").sub(/override$/, "_override")
            .sub(/pdf$/, "_pdf").to_sym] = m[1]
        end
        /\n:data-uri-image: (?<datauriimage>[^\n]+)\n/ =~ header
        /\n:(?<hier_assets>hierarchical-assets:[^\n]*)\n/ =~ header
        /\n:(?<use_xinclude>use-xinclude:[^\n]*)\n/ =~ header
        /\n:(?<break_up>break-up-urls-in-tables:[^\n]*)\n/ =~ header

        defined?(hier_assets) and
          hier_assets = empty_attr(hier_assets, "hierarchical-assets")
        defined?(use_xinclude) and
          use_xinclude = empty_attr(use_xinclude, "use-xinclude")
        defined?(break_up) and
          break_up = empty_attr(break_up, "break-up-urls-in-tables")
        ret.merge(
          datauriimage: defined?(datauriimage) ? datauriimage != "false" : nil,
          hierarchical_assets: defined?(hier_assets) ? hier_assets : nil,
          use_xinclude: defined?(use_xinclude) ? use_xinclude : nil,
          break_up_urls_in_tables: defined?(break_up) ? break_up : nil,
        ).reject { |_, val| val.nil? }
      end
    end
  end
end
