require "nokogiri"
require "metanorma-cli"
require "isodoc"
require "fileutils"

# This is only going to render the HTML collection
# ARGV[0]: input file
# ARGV[1]: output directory
#
# We presuppose that the bibdata of the document is equivalent to that of the collection,
# and that the flavour gem can sensibly process it. We may need to enhance metadata
# in the flavour gems isodoc/metadata.rb with collection metadata

def init
  @xml = Nokogiri::XML(File.read(ARGV[0], encoding: "utf-8"))
  require "metanorma-#{doctype}"
  @isodoc = isodoc
  @isodoc.metadata_init("en", "Latn", {})
  @isodoc.info(@xml, nil)
  FileUtils.rm_f ARGV[1]
  FileUtils.mkdir_p ARGV[1]
  @files = []
end

class Dummy
  def attr(_x)
  end
end

def isodoc
  x = Asciidoctor.load nil, {backend: doctype.to_sym}
  x.converter.html_converter(Dummy.new)
end

def doctype
  docid = @xml&.at(ns("//bibdata/docidentifier/@type"))&.text and
    return docid.downcase
  docid = @xml&.at(ns("//bibdata/docidentifier"))&.text and
    return docid.sub(/\s.*$/, "").lowercase
  "standoc"
end

def ns(xpath)
  IsoDoc::Convert.new({}).ns(xpath)
end

def coverpage
  File.open(File.join(ARGV[1], "cover.html"), "w:UTF-8") do |f|
    f.write  @isodoc.populate_template(File.read("collection_cover.html"))
  end
end

def indexfile_title(m)
  lvl = m&.at(ns("./level"))&.text&.capitalize
  lbl = m&.at(ns("./title"))&.text
  "#{lvl}#{ lvl && lbl ? ": ": "" }#{lbl}"
end

def indexfile_docref(m)
  return "" unless m.at(ns("./docref"))
  ret = "<ul>\n"
  m.xpath(ns("./docref")).each do |d|
    identifier = d.at(ns("./identifier")).text
    link = d["fileref"] ? d["fileref"].sub(/\.xml$/, ".html") : d["id"] + ".html"
    @files << (d["fileref"] ? {type: "fileref", id: d["fileref"]} : {type: "id", id: d["id"]})
    ret += "<li><a href='./#{link}'>#{identifier}</li>\n"
  end
  ret += "</ul>\n"
  ret
end

def indexfile(m)
  ret = "<ul>\n"
  ret += "<li>#{indexfile_title(m)}</li>\n"
  ret += indexfile_docref(m)
  m.xpath(ns("./manifest")).each do |d|
    ret += "<li>\n#{indexfile(d)}\n</li>\n"
  end
  ret += "<ul>\n"
  ret
end

def index
  File.open(File.join(ARGV[1], "index.html"), "w:UTF-8") do |f|
    f.write <<~END
<html>
<head/>
<body>
    #{indexfile(@xml.at(ns("//manifest")))}
</body>
</html>
    END
  end
end

def targetfile(x)
  if x[:type] == "fileref"
    [File.read(x[:id], encoding: "utf-8"), x[:id].sub(/\.xml$/, ".html")]
  else
    [@xml.at(ns("//doc-container[@id = '#{x[:id]}']")).to_xml, x["id"] + ".html"]
  end
end

# TODO: update crossreferences to other files in the selection
# repo(current-metanorma-collection/ISO 17301-1:2016)
# replaced by
# bibdata of "ISO 17301-1:2016" in situ as bibitem
# Any erefs to that bibitem id are replaced with relative URL
# Preferably with anchor, and is a job to realise dynamic lookup of localities
def update_xrefs(file)
  file
end

def files
  @files.each do |x|
    file, filename = targetfile(x)
    file = update_xrefs(file)
    Tempfile.open(["collection", ".xml"], encoding: "utf-8") do |f|
      f.write(file)
      f.close
      warn "metanorma compile -x html #{f.path}"
      system "metanorma compile -x html #{f.path}"
      FileUtils.mv f.path, File.join(ARGV[1], filename)
    end
  end
end

init
coverpage
index
files
