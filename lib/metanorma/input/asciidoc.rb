
module Metanorma
  module Input

    class Asciidoc < Base

      def process(file, type)
        Asciidoctor.convert(
          file,
          to_file: false,
          safe: :safe,
          backend: type,
          header_footer: true,
          attributes: %w(nodoc stem xrefstyle=short)
        )
      end

      def extract_options(file)
        header = file.sub(/\n\n.*$/m, "\n")

        /\n:script: (?<script>[^\n]+)\n/ =~ header
        /\n:body-font: (?<bodyfont>[^\n]+)\n/ =~ header
        /\n:header-font: (?<headerfont>[^\n]+)\n/ =~ header
        /\n:monospace-font: (?<monospacefont>[^\n]+)\n/ =~ header
        /\n:title-font: (?<titlefont>[^\n]+)\n/ =~ header
        /\n:i18nyaml: (?<i18nyaml>[^\n]+)\n/ =~ header
        /\n:htmlstylesheet: (?<htmlstylesheet>[^\n]+)\n/ =~ header
        /\n:htmlcoverpage: (?<htmlcoverpage>[^\n]+)\n/ =~ header
        /\n:htmlintropage: (?<htmlintropage>[^\n]+)\n/ =~ header
        /\n:scripts: (?<scripts>[^\n]+)\n/ =~ header
        /\n:scripts-pdf: (?<scripts_pdf>[^\n]+)\n/ =~ header
        /\n:wordstylesheet: (?<wordstylesheet>[^\n]+)\n/ =~ header
        /\n:standardstylesheet: (?<standardstylesheet>[^\n]+)\n/ =~ header
        /\n:header: (?<header>[^\n]+)\n/ =~ header
        /\n:wordcoverpage: (?<wordcoverpage>[^\n]+)\n/ =~ header
        /\n:wordintropage: (?<wordintropage>[^\n]+)\n/ =~ header
        /\n:ulstyle: (?<ulstyle>[^\n]+)\n/ =~ header
        /\n:olstyle: (?<olstyle>[^\n]+)\n/ =~ header
        /\n(?<datauriimage>:data-uri-image:[^\n]*)\n/ =~ header
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
          data_uri_image: defined?(datauriimage) ? true : nil,
        }.reject { |_, val| val.nil? }
      end

    end
  end
end
