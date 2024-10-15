module Metanorma
  class Compile
    def relaton_export(isodoc, options)
      options[:relaton] or return
      xml = Nokogiri::XML(isodoc, &:huge)
      bibdata = xml.at("//bibdata") || xml.at("//xmlns:bibdata")
      # docid = bibdata&.at("./xmlns:docidentifier")&.text || options[:filename]
      # outname = docid.sub(/^\s+/, "").sub(/\s+$/, "").gsub(/\s+/, "-") + ".xml"
      File.open(options[:relaton], "w:UTF-8") { |f| f.write bibdata.to_xml }
    end

    def clean_sourcecode(xml)
      xml.xpath(".//callout | .//annotation | .//xmlns:callout | "\
                ".//xmlns:annotation").each(&:remove)
      xml.xpath(".//br | .//xmlns:br").each { |x| x.replace("\n") }
      HTMLEntities.new.decode(xml.children.to_xml)
    end

    def extract(isodoc, dirname, extract_types)
      dirname or return
      extract_types.nil? || extract_types.empty? and
        extract_types = %i[sourcecode image requirement]
      FileUtils.rm_rf dirname
      FileUtils.mkdir_p dirname
      xml = Nokogiri::XML(isodoc, &:huge)
      sourcecode_export(xml, dirname) if extract_types.include? :sourcecode
      image_export(xml, dirname) if extract_types.include? :image
      extract_types.include?(:requirement) and
        requirement_export(xml, dirname)
    end

    def sourcecode_export(xml, dirname)
      xml.at("//sourcecode | //xmlns:sourcecode") or return
      FileUtils.mkdir_p "#{dirname}/sourcecode"
      xml.xpath("//sourcecode | //xmlns:sourcecode").each_with_index do |s, i|
        filename = s["filename"] || sprintf("sourcecode-%04d.txt", i)
        export_output("#{dirname}/sourcecode/#{filename}",
                      clean_sourcecode(s.dup))
      end
    end

    def image_export(xml, dirname)
      xml.at("//image | //xmlns:image") or return
      FileUtils.mkdir_p "#{dirname}/image"
      xml.xpath("//image | //xmlns:image").each_with_index do |s, i|
        next unless /^data:image/.match? s["src"]

        %r{^data:image/(?<imgtype>[^;]+);base64,(?<imgdata>.+)$} =~ s["src"]
        fn = s["filename"] || sprintf("image-%<num>04d.%<name>s",
                                      num: i, name: imgtype)
        export_output("#{dirname}/image/#{fn}", Base64.strict_decode64(imgdata),
                      binary: true)
      end
    end

    REQUIREMENT_XPATH =
      "//requirement | //xmlns:requirement | //recommendation | "\
      "//xmlns:recommendation | //permission | //xmlns:permission".freeze

    def requirement_export(xml, dirname)
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
