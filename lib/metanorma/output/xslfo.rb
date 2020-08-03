require 'mn2pdf'
require_relative "./utils.rb"

module Metanorma
  module Output
    class XslfoPdf < Base
      def convert(url_path, output_path, xsl_stylesheet)
        return if url_path.nil? || output_path.nil? || xsl_stylesheet.nil?

        Mn2pdf.convert(quote(url_path), quote(output_path), quote(xsl_stylesheet))
      end

      def quote(x)
        return x if /^'.*'$/.match(x)
        return x if /^".*"$/.match(x)
        %("#{x}")
      end
    end
  end
end

