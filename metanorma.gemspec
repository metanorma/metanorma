lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "metanorma/version"

Gem::Specification.new do |spec|
  spec.name          = "metanorma"
  spec.version       = Metanorma::VERSION
  spec.authors       = ["Ribose Inc."]
  spec.email         = ["open.source@ribose.com"]

  spec.summary       = "Metanorma is the standard of standards; the metanorma gem allows you to create any standard document type supported by Metanorma."
  spec.description   = "Library to process any Metanorma standard."
  spec.homepage      = "https://github.com/metanorma/metanorma"
  spec.license       = "BSD-2-Clause"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features|bin|.github)/}) \
    || f.match(%r{Rakefile|bin/rspec}) \
    || f.match(%r{flake|\.(?:direnv|pryrc|irbrc|nix)})
  end
  spec.extra_rdoc_files = %w[README.adoc CHANGELOG.adoc LICENSE.txt]
  spec.bindir        = "bin"
  # spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.1.0"

  spec.add_runtime_dependency "asciidoctor"
  spec.add_runtime_dependency "concurrent-ruby"
  spec.add_runtime_dependency "fontist", ">= 2.0.0"
  spec.add_runtime_dependency "htmlentities"
  spec.add_runtime_dependency "isodoc", ">= 3.0.0"
  spec.add_runtime_dependency "marcel"
  spec.add_runtime_dependency "metanorma-taste", "~> 0.1.0"
  spec.add_runtime_dependency "mn2pdf", "~> 2"
  spec.add_runtime_dependency "nokogiri"
  spec.add_development_dependency "canon", "= 0.1.3"
  spec.add_development_dependency "metanorma-iho"
  spec.add_development_dependency "metanorma-iso"

  # relaton-cli is required by Metanorma::Collection
  spec.add_dependency "relaton-cli"
end
