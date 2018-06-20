module Metanorma
  module Output
    class Pdf < Base

      def convert(url_path, output_path)
        file_url = "file://#{Dir.pwd}/#{url_path}"
        pdfjs = File.join(File.dirname(__FILE__), '../../../exe/metanorma-pdf.js')
        system "export NODE_PATH=$(npm root --quiet -g);
                      node #{pdfjs} #{file_url} #{output_path}"
      end

    end
  end
end

