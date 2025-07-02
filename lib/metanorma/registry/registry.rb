# Registry of all Metanorma types and entry points

require "singleton"
require "metanorma-taste"

class Error < StandardError
end

module Metanorma
  # Central registry for managing Metanorma processors, flavors, and their aliases
  #
  # This singleton class provides a centralized registry for:
  # - Metanorma processors (document format processors)
  # - Flavor aliases (mapping legacy/alternative names to canonical flavors)
  # - Taste configurations (via TasteRegister integration)
  #
  # The registry maintains backward compatibility with legacy flavor names while
  # integrating with the modern TasteRegister system for dynamic taste management.
  #
  # @example Basic usage
  #   registry = Metanorma::Registry.instance
  #
  #   # Register a processor
  #   registry.register(MyProcessor)
  #
  #   # Look up flavor aliases
  #   registry.alias(:csd)  # => :cc
  #
  #   # Register custom aliases
  #   registry.register_alias(:my_flavor, :iso)
  #
  # @example Finding processors
  #   processor = registry.find_processor(:iso)
  #   formats = registry.output_formats
  #   backends = registry.supported_backends
  class Registry
    include Singleton

    attr_reader :processors, :tastes

    # Default legacy aliases for backward compatibility
    # Maps old flavor names to their canonical equivalents
    DEFAULT_ALIASES = { csd: :cc, m3d: :m3aawg, mpfd: :mpfa, csand: :csa }.freeze

    # Initialize the registry with processors, tastes, and aliases
    #
    # Sets up the registry by:
    # 1. Initializing empty processors hash
    # 2. Connecting to the TasteRegister instance
    # 3. Initializing custom aliases with defaults
    def initialize
      @processors = {}
      @tastes = Metanorma::TasteRegister.instance
      @custom_aliases = DEFAULT_ALIASES.dup
    end

    # Look up the canonical flavor name for a given alias
    #
    # Checks aliases in priority order:
    # 1. Custom registered aliases (highest priority)
    # 2. Taste-based aliases from TasteRegister
    # 3. Returns nil if no alias found
    #
    # @param flavour [Symbol, String, nil] The flavor alias to look up
    # @return [Symbol, nil] The canonical flavor name, or nil if no alias exists
    #
    # @example
    #   registry.alias(:csd)  # => :cc (from DEFAULT_ALIASES)
    #   registry.alias(:icc)  # => :iso (from taste configuration)
    #   registry.alias(:unknown)  # => nil
    #   registry.alias(nil)  # => nil
    def alias(flavour)
      return nil if flavour.nil?

      flavour_sym = flavour.to_sym

      # Check custom aliases first (includes defaults)
      return @custom_aliases[flavour_sym] if @custom_aliases.key?(flavour_sym)

      # Then check taste aliases
      taste_aliases = @tastes.aliases
      taste_aliases[flavour_sym]
    end

    # Register a custom alias mapping
    #
    # Allows runtime registration of flavor aliases. Custom aliases take precedence
    # over taste-based aliases, allowing overrides of taste configurations.
    #
    # @param alias_name [Symbol, String] The alias name to register
    # @param target_flavor [Symbol, String] The canonical flavor it should map to
    #
    # @example
    #   registry.register_alias(:my_custom, :iso)
    #   registry.alias(:my_custom)  # => :iso
    #
    #   # Override a taste alias
    #   registry.register_alias(:icc, :custom_iso)
    def register_alias(alias_name, target_flavor)
      @custom_aliases[alias_name.to_sym] = target_flavor.to_sym
    end

    # Register a Metanorma processor
    #
    # Registers a processor class and automatically creates aliases for all its
    # short names. The last short name is considered the canonical name.
    #
    # @param processor [Class] A processor class that inherits from Metanorma::Processor
    # @raise [Error] If the processor doesn't inherit from Metanorma::Processor
    # @return [Array<Symbol>] Array of short names for the processor
    #
    # @example
    #   registry.register(Metanorma::ISO::Processor)
    #   # Registers processor and creates aliases for all its short names
    def register(processor)
      unless processor < ::Metanorma::Processor
        raise Error, "Processor must inherit from Metanorma::Processor"
      end

      # The last short name is the canonical name
      processor_instance = processor.new
      short_names = Array(processor_instance.short)
      canonical_name = short_names.last

      # Register processor with canonical name
      @processors[canonical_name] = processor_instance

      # Create aliases for all short names pointing to canonical name
      short_names.each { |name| @custom_aliases[name] = canonical_name }

      Util.log("[metanorma] processor \"#{short_names.first}\" registered", :info)
      short_names
    end

    # Find a registered processor by its short name
    #
    # @param short [Symbol, String] The short name of the processor to find
    # @return [Metanorma::Processor, nil] The processor instance, or nil if not found
    #
    # @example
    #   processor = registry.find_processor(:iso)
    #   processor = registry.find_processor("iso")
    def find_processor(short)
      @processors[short.to_sym]
    end

    # Get list of all supported backend names
    #
    # @return [Array<Symbol>] Array of registered processor backend names
    #
    # @example
    #   registry.supported_backends  # => [:iso, :iec, :itu, ...]
    def supported_backends
      @processors.keys
    end

    # Get output formats supported by each registered processor
    #
    # @return [Hash<Symbol, Hash>] Hash mapping processor names to their output formats
    #
    # @example
    #   registry.output_formats
    #   # => { iso: { html: "html", pdf: "pdf", ... }, iec: { ... }, ... }
    def output_formats
      @processors.inject({}) do |acc, (k, v)|
        acc[k] = v.output_formats
        acc
      end
    end

    # Get XML root tags for processors with Asciidoctor backends
    #
    # @return [Hash<Symbol, String>] Hash mapping processor names to their XML root tags
    #
    # @example
    #   registry.root_tags
    #   # => { iso: "iso-standard", iec: "iec-standard", ... }
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
