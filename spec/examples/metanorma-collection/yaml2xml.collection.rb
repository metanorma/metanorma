require "relaton-cli"
require "yaml"
require "tempfile"
require "relaton"
require "metanorma-cli"
require "nokogiri"

def main
  @collection = YAML.load_file(ARGV[0])
  @docs = []
  require "metanorma-#{doctype}"
  output
end

def output
  print <<~END
    <metanorma-collection xmlns="http://metanorma.org">
      #{collection_bibdata}
      #{manifest(@collection['manifest'])}
      #{prefatory}
      #{doccontainer}
      #{final}
    </metanorma-collection>
  END
end

def collection_bibdata
  return unless @collection["bibdata"]

  Tempfile.open(["bibdata", ".yml"], encoding: "utf-8") do |f|
    f.write(YAML.dump(@collection["bibdata"]))
    f.close
    ::Relaton::Cli::YAMLConvertor.new(f).to_xml
    File.read(f.path.sub(/\.yml$/, ".rxl"), encoding: "utf-8")
  end
end

def manifest(m)
  ret = "<manifest>\n"
  ret += "<level>#{m['level']}</level>\n" if m["level"]
  ret += "<title>#{m['title']}</title>\n" if m["title"]
  if m["docref"].is_a? Hash
    ret += docref(m["docref"])
  elsif m["docref"].is_a? Array
    Array(m["docref"]).each { |d| ret += docref(d) }
  end
  if m["manifest"].is_a? Hash
    ret += manifest(m["manifest"])
  elsif m["manifest"].is_a? Array
    m["manifest"].each { |mm| ret += manifest(mm) }
  end
  ret += "</manifest>\n"
  ret
end

def docref(d)
  @docs << { identifier: d["identifier"], fileref: d["fileref"],
             id: "doc%09d" % @docs.size }
  ret = "<docref"
  ret += if Array(@collection["directives"]).include?("documents-inline")
           %( id="#{d['id']}")
         else
           %( fileref="#{d['fileref']}")
         end
  ret += ">"
  ret += "<identifier>#{d['identifier']}</identifier>"
  ret += "</docref>\n"
  ret
end

def dummy_header
  <<~END
    = X
    A

  END
end

def prefatory
  return unless @collection["prefatory-content"]

  c = Asciidoctor.convert(dummy_header + @collection["prefatory-content"],
                          backend: doctype.to_sym, header_footer: true)
  out = Nokogiri::XML(c).at("//xmlns:sections").children.to_xml
  "<prefatory-content>\n#{out}</prefatory-content>"
end

def final
  return unless @collection["final-content"]

  c = Asciidoctor.convert(dummy_header + @collection["final-content"],
                          backend: doctype.to_sym, header_footer: true)
  out = Nokogiri::XML(c).at("//xmlns:sections").children.to_xml
  "<final-content>\n#{out}</final-content>"
end

def doccontainer
  ret = ""
  return unless Array(@collection["directives"]).include?("documents-inline")

  @docs.each do |d|
    ret += "<doc-container id=#{d[:id]}>\n"
    ret += File.read(d[:fileref], encoding: "utf-8")
    ret += "</doc-container>\n\n\n"
  end
  ret
end

def doctype
  docid = @collection["bibdata"]["docid"]["type"] and
    return docid.downcase
  docid = @collection["bibdata"]["docid"] and
    return docid.sub(/\s.*$/, "").lowercase
  "standoc"
end

main
