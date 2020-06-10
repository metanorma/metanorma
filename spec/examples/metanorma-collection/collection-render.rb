require "nokogiri"
require "metanorma-cli"
require "isodoc"
require "fileutils"

# This is only going to render the HTML collection
# ARGV[0]: input file
# ARGV[1]: cover page HTML (Liquid template)
# ARGV[2]: output directory
#
# We presuppose that the bibdata of the document is equivalent to that of the collection,
# and that the flavour gem can sensibly process it. We may need to enhance metadata
# in the flavour gems isodoc/metadata.rb with collection metadata

def init
  # @xml is the collection manifest
  @xml = Nokogiri::XML(File.read(ARGV[0], encoding: "utf-8"))
  # list of files in the collection
  @files = read_files
  require "metanorma-#{doctype}"
  @isodoc = isodoc
  # create the @meta class of isodoc, with "navigation" set to the index bar extracted from the manifest
  @isodoc.metadata_init("en", "Latn", {navigation: indexfile(@xml.at(ns("//manifest")))})
  # populate the @meta class of isodoc with the various metadata fields native to the flavour;
  # used to populate Liquid
  @isodoc.info(@xml, nil)
  FileUtils.rm_rf ARGV[2]
  FileUtils.mkdir_p ARGV[2]
end

class Dummy
  def attr(_x)
  end
end

# The isodoc class for the metanorma flavour we are using
def isodoc
  x = Asciidoctor.load nil, {backend: doctype.to_sym}
  x.converter.html_converter(Dummy.new)
end

# infer the flavour from the first document identifier; relaton does that
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

# hash for each document in collection of document identifier to:
# document reference (fileref or id), type of document reference, and bibdata entry for that file
def read_files
  files = {}
  @xml.xpath(ns("//docref")).each do |d|
    identifier = d.at(ns("./identifier")).text
    files[identifier] = (d["fileref"] ? {type: "fileref", ref: d["fileref"]} : {type: "id", ref: d["id"]})
    file, filename = targetfile(files[identifier])
    files[identifier][:bibdata] = Nokogiri::XML(file).at(ns("//bibdata"))
  end
  files
end

# populate liquid template of ARGV[1] with metadata extracted from collection manifest
def coverpage
  File.open(File.join(ARGV[2], "index.html"), "w:UTF-8") do |f|
    f.write  @isodoc.populate_template(File.read(ARGV[1]))
  end
end

def indexfile_title(m)
  lvl = m&.at(ns("./level"))&.text&.capitalize
  lbl = m&.at(ns("./title"))&.text
  "#{lvl}#{ lvl && lbl ? ": ": "" }#{lbl}"
end

# uses the identifier to label documents; other attributes (title) can be looked up
# in @files[id][:bibdata]
def indexfile_docref(m)
  return "" unless m.at(ns("./docref"))
  ret = "<ul>\n"
  m.xpath(ns("./docref")).each do |d|
    identifier = d.at(ns("./identifier")).text
    link = d["fileref"] ? d["fileref"].sub(/\.xml$/, ".html") : d["id"] + ".html"
    ret += "<li><a href='./#{link}'>#{identifier}</a></li>\n"
  end
  ret += "</ul>\n"
  ret
end

# single level navigation list, with hierarchical nesting
# if multiple lists are needed as separate HTML fragments, multiple instances of this function will be needed,
# and associated to different variables in the call to @isodoc.metadata_init (including possibly an array of HTML fragments)
def indexfile(m)
  ret = "<ul>\n"
  ret += "<li>#{indexfile_title(m)}</li>\n"
  ret += indexfile_docref(m)
  m.xpath(ns("./manifest")).each do |d|
    ret += "#{indexfile(d)}\n"
  end
  ret += "</ul>\n"
  ret
end

# return file contents + output filename for each file in the collection, given a docref entry
def targetfile(x)
  if x[:type] == "fileref"
    [File.read(x[:ref], encoding: "utf-8"), x[:ref].sub(/\.xml$/, ".html")]
  else
    [@xml.at(ns("//doc-container[@id = '#{x[:id]}']")).to_xml, x["id"] + ".html"]
  end
end

def update_bibitem(b, docid)
  docid = repo_docid(docid)
  unless @files[docid]
    warn "Cannot find crossreference to document #{docid} in document #{identifier}!"
    abort
  end
  id = b["id"]
  newbib = b.replace(@files[docid][:bibdata])
  newbib.name = "bibitem"
  newbib["id"] = id
  newbib&.at(ns("./ext"))&.remove
end

def repo_docid(docid)
  docid.sub(%r{^repo:\(current-metanorma-collection/}, "").sub(/\)$/, "")
end

# TODO: update crossreferences to other files in the selection
# repo(current-metanorma-collection/ISO 17301-1:2016)
# replaced by
# bibdata of "ISO 17301-1:2016" in situ as bibitem
# Any erefs to that bibitem id are replaced with relative URL
# Preferably with anchor, and is a job to realise dynamic lookup of localities
def update_xrefs(file, identifier)
  docxml = Nokogiri::XML(file)
  docxml.xpath(ns("//bibitem[not(ancestor::bibitem)]")).each do |b|
    docid = b&.at(ns("./docidentifier"))&.text
    next unless %r{^repo:\(current-metanorma-collection/}.match(docid)
    update_bibitem(b, docid)
    docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
      e["citeas"] = repo_docid(docid) 
    end
  end
  docxml.to_xml
end

# process each file in the collection
# files are held in memory, and altered as postprocessing
def files
  @files.each do |identifier, x|
    file, filename = targetfile(x)
    file = update_xrefs(file, identifier)
    Tempfile.open(["collection", ".xml"], encoding: "utf-8") do |f|
      f.write(file)
      f.close
      warn "metanorma compile -x html #{f.path}"
      system "metanorma compile -x html #{f.path}"
      FileUtils.mv f.path.sub(/\.xml$/, ".html"), File.join(ARGV[2], filename)
    end
  end
end

init
files
coverpage
