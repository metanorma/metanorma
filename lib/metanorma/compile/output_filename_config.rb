# frozen_string_literal: true

module Metanorma
  class Compile
    class OutputFilenameConfig
      DEFAULT_TEMPLATE = "{{ document.docidentifier | slugify }}"

      attr_reader :template

      def initialize(template = nil)
        @template = template || DEFAULT_TEMPLATE
      end

      def generate_basename(relaton_data)
        template = Liquid::Template.parse(@template)
        template.render("document" => relaton_data)
      end
    end
  end
end
