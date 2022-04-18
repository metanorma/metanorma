require "nokogiri"
require "metanorma-cli"
require "metanorma"
require "isodoc"
require "fileutils"

# This is only going to render the HTML collection
# ARGV[0]: input file
# ARGV[1]: cover page HTML (Liquid template)
# ARGV[2]: output directory
#
# We presuppose that the bibdata of the document is equivalent to that of the
# collection, # and that the flavour gem can sensibly process it. We may need
# to enhance metadata
# in the flavour gems isodoc/metadata.rb with collection metadata

def init
  # @xml is the collection manifest
  @xml = Nokogiri::XML(File.read(ARGV[0], encoding: "utf-8"))
  @lang = @xml&.at(ns("//bibdata/language"))&.text || "en"
  @script = @xml&.at(ns("//bibdata/script"))&.text || "Latn"
  @doctype = doctype
  require "metanorma-#{@doctype}"

  # output processor for flavour
  @isodoc = isodoc

  # list of files in the collection
  @files = read_files
  FileUtils.rm_rf ARGV[2]
  FileUtils.mkdir_p ARGV[2]
end

class Dummy
  def attr(_any); end
end

# The isodoc class for the metanorma flavour we are using
def isodoc
  x = Asciidoctor.load nil, { backend: @doctype.to_sym }
  isodoc = x.converter.html_converter(Dummy.new)
  # read in internationalisation
  isodoc.i18n_init(@lang, @script)
  # create the @meta class of isodoc, with "navigation" set to the index bar
  # extracted from the manifest
  isodoc.metadata_init(@lang, @script, isodoc.labels
    .merge(navigation: indexfile(@xml.at(ns("//manifest")))))
  # populate the @meta class of isodoc with the various metadata fields native
  # to the flavour; used to populate Liquid
  isodoc.info(@xml, nil)
  isodoc
end

# infer the flavour from the first document identifier; relaton does that
def doctype
  if docid = @xml&.at(ns("//bibdata/docidentifier/@type"))&.text
    doctype = docid.downcase
  elsif docid = @xml&.at(ns("//bibdata/docidentifier"))&.text
    doctype = docid.sub(/\s.*$/, "").lowercase
  else
    return "standoc"
  end
  @registry = Metanorma::Registry.instance
  t = @registry.alias(doctype.to_sym) and return t.to_s
  doctype
end

def ns(xpath)
  IsoDoc::Convert.new({}).ns(xpath)
end

# hash for each document in collection of document identifier to:
# document reference (fileref or id), type of document reference, and bibdata
# entry for that file
def read_files
  @xml.xpath(ns("//docref")).each_with_object({}) do |d, files|
    identifier = d.at(ns("./identifier")).text
    files[identifier] = (if d["fileref"]
                           { type: "fileref", ref: d["fileref"] }
                         else
                           { type: "id", ref: d["id"] }
                         end)
    file, _filename = targetfile(files[identifier], read: true)
    xml = Nokogiri::XML(file)
    files[identifier][:anchors] = read_anchors(xml)
    files[identifier][:bibdata] = xml.at(ns("//bibdata"))
  end
end

# map locality type and label (e.g. "clause" "1") to id = anchor for a document
def read_anchors(xml)
  ret = {}
  xrefs = @isodoc.xref_init(@lang, @script, @isodoc, @isodoc.labels, {})
  xrefs.parse xml
  xrefs.get.each do |k, v|
    (v[:label] && v[:type]) or next
    ret[v[:type]] ||= {}
    ret[v[:type]][v[:label]] = k
  end
  ret
end

# populate liquid template of ARGV[1] with metadata extracted from
# collection manifest
def coverpage
  File.open(File.join(ARGV[2], "index.html"), "w:UTF-8") do |f|
    f.write @isodoc.populate_template(File.read(ARGV[1]))
  end
end

def indexfile_title(manifest)
  lvl = manifest&.at(ns("./level"))&.text&.capitalize
  lbl = manifest&.at(ns("./title"))&.text
  "#{lvl}#{lvl && lbl ? ': ' : ''}#{lbl}"
end

# uses the identifier to label documents; other attributes (title) can be
# looked up in @files[id][:bibdata]
def indexfile_docref(manifest)
  return "" unless manifest.at(ns("./docref"))

  ret = "<ul>\n"
  manifest.xpath(ns("./docref")).each do |d|
    identifier = d.at(ns("./identifier")).text
    link = if d["fileref"]
             d["fileref"].sub(/\.xml$/, ".html")
           else "#{id['id']}.html"
           end
    ret += "<li><a href='./#{link}'>#{identifier}</a></li>\n"
  end
  ret += "</ul>\n"
  ret
end

# single level navigation list, with hierarchical nesting
# if multiple lists are needed as separate HTML fragments, multiple instances
# of this function will be needed, # and associated to different variables
# in the call to @isodoc.metadata_init (including possibly an array of HTML
# fragments)
def indexfile(manifest)
  ret = "<ul>\n"
  ret += "<li>#{indexfile_title(manifest)}</li>\n"
  ret += indexfile_docref(manifest)
  manifest.xpath(ns("./manifest")).each do |d|
    ret += "#{indexfile(d)}\n"
  end
  ret += "</ul>\n"
  ret
end

# return file contents + output filename for each file in the collection,
# given a docref entry
def targetfile(entry, read: false)
  if entry[:type] == "fileref"
    [read ? File.read(x[:ref], encoding: "utf-8") : nil,
     entry[:ref].sub(/\.xml$/, ".html")]
  else
    [read ? @xml.at(ns("//doc-container[@id = '#{x[:id]}']")).to_xml : nil,
     "#{entry['id']}.html"]
  end
end

def update_bibitem(b, identifier)
  docid = b&.at(ns("./docidentifier"))&.text
  unless @files[docid]
    warn "Cannot find crossreference to document #{docid} in document #{identifier}!"
    abort
  end
  id = b["id"]
  newbib = b.replace(@files[docid][:bibdata])
  newbib.name = "bibitem"
  newbib["id"] = id
  newbib&.at(ns("./ext"))&.remove
  _file, url = targetfile(@files[docid], read: false)
  newbib.at(ns("./docidentifier")).previous = %{<uri type="citation">#{url}</uri>}
end

def repo_docid(docid)
  docid.sub(%r{^current-metanorma-collection/}, "")
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
    next unless docid = b&.at(ns("./docidentifier[@type = 'repository']"))&.text
    next unless %r{^current-metanorma-collection/}.match?(docid)

    update_bibitem(b, identifier)
    update_anchors(b, docxml, docid)
  end
  docxml.to_xml
end

# if there is a crossref to another document, with no anchor, retrieve the
# anchor given the locality, and insert it into the crossref
def update_anchors(bib, docxml, _id)
  docid = bib&.at(ns("./docidentifier"))&.text
  docxml.xpath("//xmlns:eref[@citeas = '#{docid}']").each do |e|
    e.at(ns(".//locality[@type = 'anchor']")).nil? or next
    update_anchors1(e, docid)
  end
end

def update_anchors1(eref, docid)
  ins = eref.at(ns("./localityStack")) or return
  type = ins.at(ns("./locality/@type")) or return
  ref = ins.at(ns("./locality/referenceFrom")) or return
  anchor = @files[docid][:anchors][type.text][ref.text] and
    ins << "<locality type='anchor'><referenceFrom>#{anchor.sub(/^_/, '')}"\
           "</referenceFrom></locality>"
end

# process each file in the collection
# files are held in memory, and altered as postprocessing
def files
  @files.each do |identifier, x|
    file, filename = targetfile(x, read: true)
    file = update_xrefs(file, identifier)
    write_temp_file(file, filename)
  end
end

def write_temp_file(file, filename)
  Tempfile.open(["collection", ".xml"], encoding: "utf-8") do |f|
    f.write(file)
    f.close
    warn "metanorma compile -x html #{f.path}"
    system "metanorma compile -x html #{f.path}"
    FileUtils.mv f.path.sub(/\.xml$/, ".html"), File.join(ARGV[2], filename)
  end
end

init
files
coverpage
