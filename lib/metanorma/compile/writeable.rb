# frozen_string_literal: true

module Metanorma
  class Compile
    module Writeable
      def export_output(fname, content, **options)
        mode = options[:binary] ? "wb" : "w:UTF-8"
        File.open(fname, mode) { |f| f.write content }
      end
    end
  end
end
