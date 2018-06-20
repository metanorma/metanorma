module Metanorma
  module Output
    class Pdf < Base

      def convert(url_path, output_path)
        file_url = "file://#{url_path}"
        pdfjs = File.join(File.dirname(__FILE__), '../../../exe/metanorma-pdf.js')
        puts "export NODE_PATH=$(npm root --quiet -g);
                      node #{pdfjs} #{file_url} #{output_path}"
        system "export NODE_PATH=$(npm root --quiet -g);
                      node #{pdfjs} #{file_url} #{output_path}"
      end

    end
  end
end

