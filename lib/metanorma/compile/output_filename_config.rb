# frozen_string_literal: true

module Metanorma
  class Compile
    class OutputFilenameConfig
      DEFAULT_TEMPLATE = "{{ document.docidentifier | slugify }}"

      attr_reader :template

      def initialize(template = nil)
        @template = template || DEFAULT_TEMPLATE
      end

      def generate_filename(relaton_data, extension)
        template = Liquid::Template.parse(@template)
        base = template.render("document" => relaton_data)
        "#{base}.#{extension}"
      end
    end
  end
end
