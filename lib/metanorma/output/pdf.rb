module Metanorma
  module Output
    class Pdf < Base

      def convert(url_path, output_path)
        file_url = url_path
        file_url = "file://#{url_path}" if %r{^/}.match file_url
        file_url = "file://#{Dir.pwd}/#{url_path}" unless %r{^file://}.match file_url
        pdfjs = File.join(File.dirname(__FILE__), '../../../bin/metanorma-pdf.js')
        ENV['NODE_PATH'] ||= `npm root --quiet -g`.strip
        system "node #{pdfjs} #{file_url} #{output_path}"
      end
    end
  end
end

