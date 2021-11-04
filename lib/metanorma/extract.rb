module Metanorma
  class Compile
    def clean_sourcecode(xml)
      xml.xpath(".//callout | .//annotation | .//xmlns:callout | "\
                ".//xmlns:annotation").each(&:remove)
      xml.xpath(".//br | .//xmlns:br").each { |x| x.replace("\n") }
      HTMLEntities.new.decode(xml.children.to_xml)
    end

    def extract(isodoc, dirname, extract_types)
      return unless dirname

      if extract_types.nil? || extract_types.empty?
        extract_types = %i[sourcecode image requirement]
      end
      FileUtils.rm_rf dirname
      FileUtils.mkdir_p dirname
      xml = Nokogiri::XML(isodoc) { |config| config.huge }
      sourcecode_export(xml, dirname) if extract_types.include? :sourcecode
      image_export(xml, dirname) if extract_types.include? :image
      requirement_export(xml, dirname) if extract_types.include? :requirement
    end

    def sourcecode_export(xml, dirname)
      xml.at("//sourcecode | //xmlns:sourcecode") or return
      FileUtils.mkdir_p "#{dirname}/sourcecode"
      xml.xpath("//sourcecode | //xmlns:sourcecode").each_with_index do |s, i|
        filename = s["filename"] || sprintf("sourcecode-%04d.txt", i)
        File.open("#{dirname}/sourcecode/#{filename}", "w:UTF-8") do |f|
          f.write clean_sourcecode(s.dup)
        end
      end
    end

    def image_export(xml, dirname)
      xml.at("//image | //xmlns:image") or return
      FileUtils.mkdir_p "#{dirname}/image"
      xml.xpath("//image | //xmlns:image").each_with_index do |s, i|
        next unless /^data:image/.match? s["src"]

        %r{^data:image/(?<imgtype>[^;]+);base64,(?<imgdata>.+)$} =~ s["src"]
        filename = s["filename"] || sprintf("image-%04d.%s", i, imgtype)
        File.open("#{dirname}/image/#{filename}", "wb") do |f|
          f.write(Base64.strict_decode64(imgdata))
        end
      end
    end

    REQUIREMENT_XPATH = "//requirement | //xmlns:requirement | "\
                        "//recommendation | //xmlns:recommendation | //permission | "\
                        "//xmlns:permission".freeze

    def requirement_export(xml, dirname)
      xml.at(REQUIREMENT_XPATH) or return
      FileUtils.mkdir_p "#{dirname}/requirement"
      xml.xpath(REQUIREMENT_XPATH).each_with_index do |s, i|
        filename = s["filename"] || sprintf("%s-%04d.xml", s.name, i)
        File.open("#{dirname}/requirement/#{filename}", "w:UTF-8") do |f|
          f.write s
        end
      end
    end
  end
end
