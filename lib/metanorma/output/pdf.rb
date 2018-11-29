require "phantomjs"

module Metanorma
  module Output
    class Pdf < Base

      def convert(url_path, output_path)
        file_url = "file://#{Dir.pwd}/#{url_path}"
        #pdfjs = File.join(File.dirname(__FILE__), '../../../bin/metanorma-pdf.js')
        #system "export NODE_PATH=$(npm root --quiet -g); node #{pdfjs} #{file_url} #{output_path}"
        Phantomjs.path
        pdfjs = File.join(File.dirname(__FILE__), "../../../bin/rasterize.js", "A4")
        Phantomjs.run(pdfjs, file_url, output_path)
      end
    end
  end
end

