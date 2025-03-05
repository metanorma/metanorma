# frozen_string_literal: true

module Metanorma
  class Compile
    class OutputFilenameConfig
      DEFAULT_TEMPLATE =
        "{{ document.docidentifier | downcase" \
        " | replace: '/' , '-'" \
        " | replace: ' ' , '-' }}"

      attr_reader :template

      def initialize(template)
        @template = if template.nil? || template.empty?
                      DEFAULT_TEMPLATE
                    else
                      template
                    end
      end

      def generate_filename(relaton_data)
        template = Liquid::Template.parse(@template)
        template.render("document" => relaton_data)
      end
    end
  end
end
