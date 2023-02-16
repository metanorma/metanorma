module Metanorma
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
        doc = Nokogiri::XML(File.read(filename, encoding: "UTF-8")) do |config|
          config.huge
        end
        new(doc, filename, raw: true)
      end

      def attachment_bibitem(identifier)
        Nokogiri::XML <<~DOCUMENT
          <bibdata><docidentifier>#{identifier}</docidentifier></bibdata>
        DOCUMENT
      end

      private

      # #param xml [Nokogiri::XML::Document, Nokogiri::XML::Element]
      # @return [RelatonBib::BibliographicItem,RelatonIso::IsoBibliographicItem]
      def from_xml(xml)
        Relaton::Cli.parse_xml xml.at("//xmlns:bibitem|//xmlns:bibdata")
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
            from_xml Nokogiri::XML(File.read(file, encoding: "UTF-8"))
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
      first = @bibitem.docidentifier.first
      @type ||= (first&.type&.downcase ||
                 first&.id&.match(/^[^\s]+/)&.to_s)&.downcase ||
        "standoc"
    end

    private

    def render_xml(builder)
      if @raw
        #builder << @bibitem.root.to_xml
        builder.parent.add_child(@bibitem.root)
      else
        builder.send("#{type}-standard") do |b|
          b << @bibitem.to_xml(bibdata: true)
        end
      end
    end
  end
end
