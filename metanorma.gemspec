
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "metanorma/version"

Gem::Specification.new do |spec|
  spec.name          = "metanorma"
  spec.version       = Metanorma::VERSION
  spec.authors       = ['Ribose Inc.']
  spec.email         = ['open.source@ribose.com']

  spec.summary       = %q{Metanorma is the standard of standards; the metanorma gem allows you to create any standard document type supported by Metanorma.}
  spec.description   = %q{Library to process any Metanorma standard.}
  spec.homepage      = "https://github.com/metanorma/metanorma"
  spec.license       = "BSD-2-Clause"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.extra_rdoc_files = %w[README.adoc CHANGELOG.adoc LICENSE.txt]
  spec.bindir        = "bin"
  #spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = '>= 2.4.0'

  spec.add_runtime_dependency 'asciidoctor'
  spec.add_runtime_dependency 'htmlentities'
  spec.add_runtime_dependency 'nokogiri'
  spec.add_runtime_dependency 'mn2pdf', "~> 1"
  spec.add_runtime_dependency 'pry'
  spec.add_runtime_dependency "fontist", "~> 1.5.0"
# get relaton-cli to avoic circular reference with metanorma-standoc
  #spec.add_dependency "relaton-cli"
  #spec.add_dependency "metanorma-standoc", "~> 1.5.3"

  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "byebug", "~> 10.0"
  spec.add_development_dependency "rspec-command", "~> 1.0"
  spec.add_development_dependency "equivalent-xml", "~> 0.6"
  spec.add_development_dependency "metanorma-iso", "~> 1.5.8"
  spec.add_development_dependency "sassc", "~> 2.4.0"
  #spec.add_development_dependency "isodoc", "~> 1.2.1"
end
