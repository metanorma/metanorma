# Registry of all Metanorma types and entry points

require "singleton"

class Error < StandardError
end

module Metanorma
  class Registry
    include Singleton

    attr_reader :processors

    # TODO: make aliases configurable
    def initialize
      @processors = {}
      @aliases = { csd: :cc, m3d: :m3aawg, mpfd: :mpfa, csand: :csa,
                   icc: :iso }
    end

    def alias(flavour)
      @aliases[flavour]
    end

    def register(processor)
      processor < ::Metanorma::Processor or raise Error
      p = processor.new
      # p.short[-1] is the canonical name
      short = Array(p.short)
      @processors[short[-1]] = p
      short.each { |s| @aliases[s] = short[-1] }
      Array(p.short)
      Util.log("[metanorma] processor \"#{Array(p.short)[0]}\" registered", :info)
    end

    def find_processor(short)
      @processors[short.to_sym]
    end

    def supported_backends
      @processors.keys
    end

    def output_formats
      @processors.inject({}) do |acc, (k, v)|
        acc[k] = v.output_formats
        acc
      end
    end

    def root_tags
      @processors.inject({}) do |acc, (k, v)|
        if v.asciidoctor_backend
          x = Asciidoctor.load nil, { backend: v.asciidoctor_backend }
          acc[k] = x.converter.xml_root_tag
        end
        acc
      end
    end
  end
end
