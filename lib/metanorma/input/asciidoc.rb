module Metanorma
  module Input

    class Asciidoc < Base

      def process(file, filename, type)
        require "asciidoctor"
        ::Asciidoctor.convert(
          file,
          to_file: false,
          safe: :safe,
          backend: type,
          header_footer: true,
          attributes: ["nodoc", "stem", "xrefstyle=short", "docfile=#{filename}"]
        )
      end

      def extract_metanorma_options(file)
        headerextract = file.sub(/\n\n.*$/m, "\n")
        /\n:mn-document-class: (?<type>[^\n]+)\n/ =~ headerextract
        /\n:mn-output-extensions: (?<extensions>[^\n]+)\n/ =~ headerextract
        {
          type: defined?(type) ? type : nil,
          extensions: defined?(extensions) ? extensions : nil,
        }.reject { |_, val| val.nil? }
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
        /\n:htmlcoverpage: (?<htmlcoverpage>[^\n]+)\n/ =~ headerextract
        /\n:htmlintropage: (?<htmlintropage>[^\n]+)\n/ =~ headerextract
        /\n:scripts: (?<scripts>[^\n]+)\n/ =~ headerextract
        /\n:scripts-pdf: (?<scripts_pdf>[^\n]+)\n/ =~ headerextract
        /\n:wordstylesheet: (?<wordstylesheet>[^\n]+)\n/ =~ headerextract
        /\n:standardstylesheet: (?<standardstylesheet>[^\n]+)\n/ =~ headerextract
        /\n:header: (?<header>[^\n]+)\n/ =~ headerextract
        /\n:wordcoverpage: (?<wordcoverpage>[^\n]+)\n/ =~ headerextract
        /\n:wordintropage: (?<wordintropage>[^\n]+)\n/ =~ headerextract
        /\n:ulstyle: (?<ulstyle>[^\n]+)\n/ =~ headerextract
        /\n:olstyle: (?<olstyle>[^\n]+)\n/ =~ headerextract
        /\n:data-uri-image: (?<datauriimage>[^\n]+)\n/ =~ headerextract
        {
          script: defined?(script) ? script : nil,
          bodyfont: defined?(bodyfont) ? bodyfont : nil,
          headerfont: defined?(headerfont) ? headerfont : nil,
          monospacefont: defined?(monospacefont) ? monospacefont : nil,
          titlefont: defined?(titlefont) ? titlefont : nil,
          i18nyaml: defined?(i18nyaml) ? i18nyaml : nil,
          htmlstylesheet: defined?(htmlstylesheet) ? htmlstylesheet : nil,
          htmlcoverpage: defined?(htmlcoverpage) ? htmlcoverpage : nil,
          htmlintropage: defined?(htmlintropage) ? htmlintropage : nil,
          scripts: defined?(scripts) ? scripts : nil,
          scripts_pdf: defined?(scripts_pdf) ? scripts_pdf : nil,
          wordstylesheet: defined?(wordstylesheet) ? wordstylesheet : nil,
          standardstylesheet: defined?(standardstylesheet) ? standardstylesheet : nil,
          header: defined?(header) ? header : nil,
          wordcoverpage: defined?(wordcoverpage) ? wordcoverpage : nil,
          wordintropage: defined?(wordintropage) ? wordintropage : nil,
          ulstyle: defined?(ulstyle) ? ulstyle : nil,
          olstyle: defined?(olstyle) ? olstyle : nil,
          datauriimage: defined?(datauriimage) ? datauriimage != "false" : nil,
        }.reject { |_, val| val.nil? }
      end

    end
  end
end
