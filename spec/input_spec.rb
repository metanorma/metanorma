require_relative "spec_helper"
require "fileutils"

RSpec.describe Metanorma::Input::Asciidoc do
  it "extracts Asciidoctor document attributes" do
    expect(Hash[Metanorma::Input::Asciidoc.new().extract_options(<<~"INPUT").sort].to_s + "\n").to eq <<~"OUTPUT"
      = Document title
      Author
      :script: a
      :body-font: b
      :header-font: c
      :title-font: d
      :i18nyaml: e
      :htmlstylesheet: f
      :htmlcoverpage: g
      :htmlintropage: h
      :scripts: i
      :scripts-pdf: j
      :wordstylesheet: k
      :standardstylesheet: l
      :header: m
      :wordcoverpage: n
      :wordintropage: o
      :ulstyle: p
      :olstyle: q
      :data-uri-image:
      INPUT
      {:bodyfont=>"b", :datauriimage=>true, :header=>"m", :headerfont=>"c", :htmlcoverpage=>"g", :htmlintropage=>"h", :htmlstylesheet=>"f", :i18nyaml=>"e", :script=>"a", :scripts=>"i", :scripts_pdf=>"j", :standardstylesheet=>"l", :titlefont=>"d", :wordstylesheet=>"k"}
    OUTPUT

  end
end
