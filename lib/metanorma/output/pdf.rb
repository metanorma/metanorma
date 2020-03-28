require "open3"
require "pathname"
require "shellwords"

module Metanorma
  module Output
    class Pdf < Base

      def convert(url_path, output_path)
        file_url = url_path
        file_url = "file://#{url_path}" if Pathname.new(file_url).absolute?
        file_url = "file://#{Dir.pwd}/#{url_path}" unless %r{^file://} =~ file_url
        pdfjs = File.join(File.dirname(__FILE__), "../../../bin/metanorma-pdf.js")

        node_path = ENV["NODE_PATH"] || `npm root --quiet -g`.strip
        node_cmd = ["node", pdfjs, file_url, output_path].map { |arg| shellescape(arg) }.join(" ")

        _, error_str, status = Open3.capture3({ "NODE_PATH" => node_path }, node_cmd)
        raise error_str unless status.success?
      end

      def shellescape(str)
        if Gem.win_platform?()
          # https://bugs.ruby-lang.org/issues/16741
          str.match(" ") ? "\"#{str}\"" : str
        else
          Shellwords.shellescape(str)
        end
      end
    end
  end
end

