require "nokogiri"

module Metanorma
  module Input

    class Asciidoc < Base

      def process(file, filename, type, options = {})
        require "asciidoctor"
        out_opts = {
          to_file: false,
          safe: :safe,
          backend: type,
          header_footer: true,
          attributes: [
            "nodoc", "stem", "xrefstyle=short", "docfile=#{filename}",
            "output_dir=#{options[:output_dir]}"
          ]
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
          previous_stderr, $stderr = $stderr, StringIO.new
          ::Asciidoctor.load(file, options)
          %r{(\n|^)asciidoctor: ERROR: ['"]?#{Regexp.escape(filename || 
            "<empty>")}['"]?: line \d+: include file not found: }.match($stderr.string) and
              err = $stderr.string
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
        asciimath = defined?(asciimath) ?
          (!asciimath.nil? && asciimath != ":mn-keep-asciimath: false") : nil
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

      def extract_options(file)
        headerextract = file.sub(/\n\n.*$/m, "\n")

        /\n:script: (?<script>[^\n]+)\n/ =~ headerextract
        /\n:body-font: (?<bodyfont>[^\n]+)\n/ =~ headerextract
        /\n:header-font: (?<headerfont>[^\n]+)\n/ =~ headerextract
        /\n:monospace-font: (?<monospacefont>[^\n]+)\n/ =~ headerextract
        /\n:title-font: (?<titlefont>[^\n]+)\n/ =~ headerextract
        /\n:i18nyaml: (?<i18nyaml>[^\n]+)\n/ =~ headerextract
        /\n:htmlstylesheet: (?<htmlstylesheet>[^\n]+)\n/ =~ headerextract
        /\n:htmlstylesheet-override: (?<htmlstylesheet_override>[^\n]+)\n/ =~ headerextract
        /\n:htmlcoverpage: (?<htmlcoverpage>[^\n]+)\n/ =~ headerextract
        /\n:htmlintropage: (?<htmlintropage>[^\n]+)\n/ =~ headerextract
        /\n:scripts: (?<scripts>[^\n]+)\n/ =~ headerextract
        /\n:scripts-pdf: (?<scripts_pdf>[^\n]+)\n/ =~ headerextract
        /\n:wordstylesheet: (?<wordstylesheet>[^\n]+)\n/ =~ headerextract
        /\n:wordstylesheet-override: (?<wordstylesheet_override>[^\n]+)\n/ =~ headerextract
        /\n:standardstylesheet: (?<standardstylesheet>[^\n]+)\n/ =~ headerextract
        /\n:header: (?<header>[^\n]+)\n/ =~ headerextract
        /\n:wordcoverpage: (?<wordcoverpage>[^\n]+)\n/ =~ headerextract
        /\n:wordintropage: (?<wordintropage>[^\n]+)\n/ =~ headerextract
        /\n:ulstyle: (?<ulstyle>[^\n]+)\n/ =~ headerextract
        /\n:olstyle: (?<olstyle>[^\n]+)\n/ =~ headerextract
        /\n:data-uri-image: (?<datauriimage>[^\n]+)\n/ =~ headerextract
        /\n:htmltoclevels: (?<htmltoclevels>[^\n]+)\n/ =~ headerextract
        /\n:doctoclevels: (?<doctoclevels>[^\n]+)\n/ =~ headerextract
        /\n:(?<hierarchical_assets>hierarchical-assets:[^\n]*)\n/ =~ headerextract
        /\n:(?<use_xinclude>use-xinclude:[^\n]*)\n/ =~ headerextract
        /\n:(?<break_up_urls_in_tables>break-up-urls-in-tables:[^\n]*)\n/ =~ headerextract

        defined?(hierarchical_assets) and
          hierarchical_assets = empty_attr(hierarchical_assets, "hierarchical-assets")
        defined?(use_xinclude) and
          use_xinclude = empty_attr(use_xinclude, "use-xinclude")
        defined?(break_up_urls_in_tables) and
          break_up_urls_in_tables = empty_attr(break_up_urls_in_tables, "break-up-urls-in-tables")
        {
          script: defined?(script) ? script : nil,
          bodyfont: defined?(bodyfont) ? bodyfont : nil,
          headerfont: defined?(headerfont) ? headerfont : nil,
          monospacefont: defined?(monospacefont) ? monospacefont : nil,
          titlefont: defined?(titlefont) ? titlefont : nil,
          i18nyaml: defined?(i18nyaml) ? i18nyaml : nil,
          htmlstylesheet: defined?(htmlstylesheet) ? htmlstylesheet : nil,
          htmlstylesheet_override: defined?(htmlstylesheet_override) ? htmlstylesheet_override : nil,
          htmlcoverpage: defined?(htmlcoverpage) ? htmlcoverpage : nil,
          htmlintropage: defined?(htmlintropage) ? htmlintropage : nil,
          scripts: defined?(scripts) ? scripts : nil,
          scripts_pdf: defined?(scripts_pdf) ? scripts_pdf : nil,
          wordstylesheet: defined?(wordstylesheet) ? wordstylesheet : nil,
          wordstylesheet_override: defined?(wordstylesheet_override) ? wordstylesheet_override : nil,
          standardstylesheet: defined?(standardstylesheet) ? standardstylesheet : nil,
          header: defined?(header) ? header : nil,
          wordcoverpage: defined?(wordcoverpage) ? wordcoverpage : nil,
          wordintropage: defined?(wordintropage) ? wordintropage : nil,
          ulstyle: defined?(ulstyle) ? ulstyle : nil,
          olstyle: defined?(olstyle) ? olstyle : nil,
          datauriimage: defined?(datauriimage) ? datauriimage != "false" : nil,
          htmltoclevels: defined?(htmltoclevels) ? htmltoclevels : nil,
          doctoclevels: defined?(doctoclevels) ? doctoclevels : nil,
          hierarchical_assets: defined?(hierarchical_assets) ? hierarchical_assets : nil,
          use_xinclude: defined?(use_xinclude) ? use_xinclude : nil,
          break_up_urls_in_tables: defined?(break_up_urls_in_tables) ? break_up_urls_in_tables : nil,
        }.reject { |_, val| val.nil? }
      end

    end
  end
end
