require "relaton-cli"

module Metanorma
  class Collection
    class Document
      # @return [Strin]
      attr_reader :file, :attachment, :bibitem, :index

      # @param bibitem [RelatonBib::BibliographicItem]
      def initialize(bibitem, file, options = {})
        @bibitem = bibitem
        @file = file
        @attachment = options[:attachment]
        @index = options[:index]
        @index = true if @index.nil?
        @raw = options[:raw]
      end

      class << self
        # @param file [String] file path
        # @param attachment [Bool] is an attachment
        # @param identifier [String] is the identifier assigned the file
        # in the collection file
        # @param index [Bool] is indication on whether to index this file in coverpage
        # @return [Metanorma::Document]
        def parse_file(file, attachment, identifier = nil, index = true)
          new(bibitem(file, attachment, identifier), file,
              { attachment: attachment, index: index })
        end

        # #param xml [Nokogiri::XML::Document, Nokogiri::XML::Element]
        # @return [Metanorma::Document]
        def parse_xml(xml)
          new from_xml(xml)
        end

        # raw XML file, can be used to put in entire file instead of just bibitem
        def raw_file(filename)
          doc = Nokogiri::XML(File.read(filename, encoding: "UTF-8"), &:huge)
          new(doc, filename, raw: true)
        end

        def attachment_bibitem(identifier)
          Nokogiri::XML <<~DOCUMENT
            <bibdata><docidentifier>#{identifier}</docidentifier></bibdata>
          DOCUMENT
        end

        private

        # Select the appropriate Relaton parser class for the given flavor tag.
        # @param tag [String, nil] flavor tag (e.g. "iso", "ietf")
        # @param bibdata [Boolean] true when parsing a <bibdata> element (has <ext>);
        #   false when parsing a <bibitem> element (no <ext>)
        # @return [Class] Relaton parser class (Bibdata or Bibitem subclass)
        def mn2relaton_parser(tag, bibdata: false)
          case tag
          when "bipm"
            require "relaton/bipm" unless defined?(::Relaton::Bipm::Bibdata)
            bibdata ? ::Relaton::Bipm::Bibdata : ::Relaton::Bipm::Bibitem
          when "bsi"
            require "relaton/bsi" unless defined?(::Relaton::Bsi::Bibdata)
            bibdata ? ::Relaton::Bsi::Bibdata : ::Relaton::Bsi::Bibitem
          when "ietf"
            require "relaton/ietf" unless defined?(::Relaton::Ietf::Bibdata)
            bibdata ? ::Relaton::Ietf::Bibdata : ::Relaton::Ietf::Bibitem
          when "iho"
            require "relaton/iho" unless defined?(::Relaton::Iho::Bibdata)
            bibdata ? ::Relaton::Iho::Bibdata : ::Relaton::Iho::Bibitem
          when "itu"
            require "relaton/itu" unless defined?(::Relaton::Itu::Bibdata)
            bibdata ? ::Relaton::Itu::Bibdata : ::Relaton::Itu::Bibitem
          when "iec"
            require "relaton/iec" unless defined?(::Relaton::Iec::Bibdata)
            bibdata ? ::Relaton::Iec::Bibdata : ::Relaton::Iec::Bibitem
          when "iso"
            require "relaton/iso" unless defined?(::Relaton::Iso::Bibdata)
            bibdata ? ::Relaton::Iso::Bibdata : ::Relaton::Iso::Bibitem
          when "nist"
            require "relaton/nist" unless defined?(::Relaton::Nist::Bibdata)
            bibdata ? ::Relaton::Nist::Bibdata : ::Relaton::Nist::Bibitem
          when "ogc"
            require "relaton/ogc" unless defined?(::Relaton::Ogc::Bibdata)
            bibdata ? ::Relaton::Ogc::Bibdata : ::Relaton::Ogc::Bibitem
          else
            bibdata ? ::Relaton::Bib::Bibdata : ::Relaton::Bib::Bibitem
          end
        rescue LoadError => e
          warn "Warning: Failed to load relaton gem for '#{tag}': #{e.message}. Falling back to Relaton::Bib::Bibdata/Bibitem"
          bibdata ? ::Relaton::Bib::Bibdata : ::Relaton::Bib::Bibitem
        end

        # #param xml [Nokogiri::XML::Document, Nokogiri::XML::Element]
        # @return [RelatonBib::BibliographicItem,RelatonIso::IsoBibliographicItem]
        def from_xml(xml)
          b = xml.at("//xmlns:bibitem|//xmlns:bibdata")
          # <bibitem> elements are always flavor-independent: use the base
          # Relaton::Bib::Bibitem regardless of collection flavor.
          # <bibdata> elements carry flavor-specific metadata (<ext> etc.) and
          # must be parsed with the appropriate flavor Bibdata class.
          r = if b.name == "bibitem"
                ::Relaton::Bib::Bibitem
              else
                mn2relaton_parser(xml.root["flavor"], bibdata: true)
              end
          # Relaton doesn't understand Pres XML tags
          b.xpath("//xmlns:fmt-identifier").each(&:remove)
          r.from_xml(b.to_xml)
        end

        # @param file [String]
        # @return [Symbol] file type
        def format(file)
          case file
          when /\.xml$/ then :xml
          when /.ya?ml$/ then :yaml
          end
        end

        # @param file [String]
        # @return [RelatonBib::BibliographicItem,
        #   RelatonIso::IsoBibliographicItem]
        def bibitem(file, attachment, identifier)
          if attachment then attachment_bibitem(identifier)
          else
            case format(file)
            when :xml
              from_xml (Nokogiri::XML(File.read(file, encoding: "UTF-8"),
                                      &:huge))
            when :yaml
              yaml = File.read(file, encoding: "UTF-8")
              Relaton::Cli::YAMLConvertor.convert_single_file(yaml)
            end
          end
        end
      end

      # @param builder [Nokogiri::XML::Builder, nil]
      # @return [Nokogiri::XML::Builder, String]
      def to_xml(builder = nil)
        if builder
          render_xml builder
        else
          Nokogiri::XML::Builder.new do |b|
            root = render_xml b
            root["xmlns"] = "http://metanorma.org"
          end.to_xml
        end
      end

      # @return [String]
      def type
        first = @bibitem.docidentifier&.first
        @type ||= (first&.type&.downcase ||
                   first&.content&.match(/^[^\s]+/)&.to_s)&.downcase ||
          "standoc"
      end

      private

      def render_xml(builder)
        if @raw
          builder.parent.add_child(@bibitem.root)
        else
          builder.send(:metanorma) do |b|
            b << @bibitem.to_xml(bibdata: true)
          end
        end
      end
    end
  end
end
