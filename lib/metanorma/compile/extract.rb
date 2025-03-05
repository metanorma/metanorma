# frozen_string_literal: true

require_relative "writeable"

module Metanorma
  class Compile
    module Extract
      # @param isodoc [String] the XML document
      # @param dirname [String, nil] the directory to extract to
      # @param extract_types [Array<Symbol>, nil] the types to extract
      # @return [void]
      def self.extract(isodoc, dirname, extract_types)
        dirname or return
        extract_types.nil? || extract_types.empty? and
          extract_types = %i[sourcecode image requirement]
        FileUtils.rm_rf dirname
        FileUtils.mkdir_p dirname
        xml = Nokogiri::XML(isodoc, &:huge)
        extract_types.each do |type|
          case type
          when :sourcecode
            export_sourcecode(xml, dirname)
          when :image
            export_image(xml, dirname)
          when :requirement
            export_requirement(xml, dirname)
          end
        end
      end

      class << self
        include Writeable

        private

        # @param xml [Nokogiri::XML::Document] the XML document
        # @return [String] the cleaned sourcecode
        def clean_sourcecode(xml)
          xml.xpath(".//callout | .//annotation | .//xmlns:callout | "\
                    ".//xmlns:annotation").each(&:remove)
          xml.xpath(".//br | .//xmlns:br").each { |x| x.replace("\n") }
          a = xml.at("./body | ./xmlns:body") and xml = a
          HTMLEntities.new.decode(xml.children.to_xml)
        end

        def export_sourcecode(xml, dirname)
          xml.at("//sourcecode | //xmlns:sourcecode") or return
          FileUtils.mkdir_p "#{dirname}/sourcecode"
          xml.xpath("//sourcecode | //xmlns:sourcecode").each_with_index do |s, i|
            filename = s["filename"] || sprintf("sourcecode-%04d.txt", i)
            export_output("#{dirname}/sourcecode/#{filename}",
                          clean_sourcecode(s.dup))
          end
        end

        def export_image(xml, dirname)
          xml.at("//image | //xmlns:image") or return
          FileUtils.mkdir_p "#{dirname}/image"
          xml.xpath("//image | //xmlns:image").each_with_index do |s, i|
            next unless /^data:image/.match? s["src"]

            %r{^data:image/(?<imgtype>[^;]+);base64,(?<imgdata>.+)$} =~ s["src"]
            fn = s["filename"] || sprintf("image-%<num>04d.%<name>s",
                                          num: i, name: imgtype)
            export_output(
              "#{dirname}/image/#{fn}",
              Base64.strict_decode64(imgdata),
              binary: true,
            )
          end
        end

        REQUIREMENT_XPATH =
          "//requirement | //xmlns:requirement | //recommendation | "\
          "//xmlns:recommendation | //permission | //xmlns:permission"

        def export_requirement(xml, dirname)
          xml.at(REQUIREMENT_XPATH) or return
          FileUtils.mkdir_p "#{dirname}/requirement"
          xml.xpath(REQUIREMENT_XPATH).each_with_index do |s, i|
            fn = s["filename"] ||
              sprintf("%<name>s-%<num>04d.xml", name: s.name, num: i)
            export_output("#{dirname}/requirement/#{fn}", s)
          end
        end
      end
    end
  end
end
