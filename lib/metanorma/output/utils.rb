require "pathname"

module Metanorma
  module Output
    module Utils
      class << self
        def file_path(url_path)
          file_url = url_path
          file_url = "file://#{url_path}" if Pathname.new(file_url).absolute?
          %r{^file://}.match?(file_url) or
            file_url = "file://#{Dir.pwd}/#{url_path}"
          file_url
        end
      end
    end
  end
end
