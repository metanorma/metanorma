require "open3"
require_relative "./utils.rb"

module Metanorma
  module Output
    class Pdf < Base

      def convert(url_path, output_path)
        file_url = Utils::file_path(url_path)
        pdfjs = File.join(File.dirname(__FILE__), "../../../bin/metanorma-pdf.js")

        node_path = ENV["NODE_PATH"] || `npm root --quiet -g`.strip
        node_cmd = ["node", pdfjs, file_url, output_path].join(" ")

        _, error_str, status = Open3.capture3({ "NODE_PATH" => node_path }, node_cmd)
        raise error_str unless status.success?
      end
    end
  end
end

