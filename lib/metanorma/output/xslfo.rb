require "open3"
require "tempfile"
require_relative "./utils.rb"

module Metanorma
  module Output
    class XslfoPdf < Base
      def convert(url_path, output_path, xsl_stylesheet)
        return if url_path.nil? || output_path.nil? || xsl_stylesheet.nil?
        pdfjar = File.join(File.dirname(__FILE__), "../../../bin/mn2pdf.jar")
        cmd = ["java", "-jar", pdfjar, "--xml-file", url_path, "--xsl-file",
               xsl_stylesheet, "--pdf-file", output_path].join(" ")
        _, error_str, status = Open3.capture3(cmd)
        raise error_str unless status.success?
      end
    end
  end
end

