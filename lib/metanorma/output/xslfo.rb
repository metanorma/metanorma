require "open3"
require "tempfile"
require_relative "./utils.rb"

module Metanorma
  module Output
    class XslfoPdf < Base
      def fontconfig
        Tempfile.open(["pdf_fonts_config", ".xml"]) do |f|
          f.write(File.read(File.join(File.dirname(__FILE__), "pdf_fonts_config.xml")).
                  gsub(/{FONTS}/, Utils::file_path(ENV["MN_PDF_FONT_PATH"])))
          f.path
        end
      end

      def convert(url_path, output_path, xsl_stylesheet)
        return if url_path.nil? || output_path.nil? || xsl_stylesheet.nil?
        pdfjar = File.join(File.dirname(__FILE__), "../../../bin/mn2pdf.jar")
<<<<<<< HEAD
        #cmd = ["java", "-jar", pdfjar, fontconfig, url_path, xsl_stylesheet, output_path].join(" ")
        cmd = ["java", "-jar", pdfjar, "--xml-file", url_path, "--xsl-file", xsl_stylesheet, "--pdf-file", output_path].join(" ")
=======
        cmd = ["java", "-jar", pdfjar, fontconfig, url_path, xsl_stylesheet, output_path].join(" ")
>>>>>>> 5e271f7c4d10be3685b8633df2e27bfac15ce585
        _, error_str, status = Open3.capture3(cmd)
        raise error_str unless status.success?
      end
    end
  end
end

