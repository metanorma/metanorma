require 'mn2pdf'
require_relative "./utils.rb"

module Metanorma
  module Output
    class XslfoPdf < Base
      def convert(url_path, output_path, xsl_stylesheet)
        return if url_path.nil? || output_path.nil? || xsl_stylesheet.nil?

        Mn2pdf.convert(url_path, output_path, xsl_stylesheet)
      end
    end
  end
end

