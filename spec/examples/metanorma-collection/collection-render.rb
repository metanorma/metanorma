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
  require "byebug"; byebug
  @isodoc.info(@xml, nil)
  FileUtils.rm_f ARGV[1]
  FileUtils.mkdir_p ARGV[1]
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

init
File.open(File.join(ARGV[1], "cover.html"), "w:UTF-8") do |f|
  f.write  @isodoc.populate_template(File.read("collection_cover.html"))
end
