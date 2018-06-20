
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
        header = file.sub(/\n\n.*$/m, "")

        /\nscript: (?<script>[^\n]+)\n/ =~ header
        /\nbody-font: (?<bodyfont>[^\n]+)\n/ =~ header
        /\nheader-font: (?<headerfont>[^\n]+)\n/ =~ header
        /\nmonospace-font: (?<monospacefont>[^\n]+)\n/ =~ header
        /\ntitle-font: (?<titlefont>[^\n]+)\n/ =~ header
        /\ni18nyaml: (?<ni18nyaml>[^\n]+)\n/ =~ header
        {
          script: defined?(script) ? script : nil,
          bodyfont: defined?(bodyfont) ? bodyfont : nil,
          headerfont: defined?(headerfont) ? headerfont : nil,
          monospacefont: defined?(monospacefont) ? monospacefont : nil,
          titlefont: defined?(titlefont) ? titlefont : nil,
          i18nyaml: defined?(i18nyaml) ? i18nyaml : nil,
        }.reject { |_, val| val.nil? }.map
      end

    end
  end
end
