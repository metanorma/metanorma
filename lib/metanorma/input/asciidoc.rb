
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
        /\n:i18nyaml: (?<ni18nyaml>[^\n]+)\n/ =~ header
        {
          script: defined?(script) ? script : nil,
          bodyfont: defined?(bodyfont) ? bodyfont : nil,
          headerfont: defined?(headerfont) ? headerfont : nil,
          monospacefont: defined?(monospacefont) ? monospacefont : nil,
          titlefont: defined?(titlefont) ? titlefont : nil,
          i18nyaml: defined?(i18nyaml) ? i18nyaml : nil,
        }.reject { |_, val| val.nil? }
      end

    end
  end
end
