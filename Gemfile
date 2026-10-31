Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}" }

gemspec

gem "metanorma-core", ">= 0.2.5"

# taste stack the compile specs exercise: the oiml taste registers the
# flavor and lazily requires metanorma-oiml (OIML STS transformers,
# unreleased); mko main carries the model-side export entry.
# Lives here, not in Gemfile.devel: consumer workflows may rewrite the
# devel overlay (fontist CI appends its path pin to it), and the repo's
# own compile specs must not depend on its survival.
gem "metanorma-taste", "~> 1.1"
gem "metanorma-oiml", github: "metanorma/metanorma-oiml", branch: "main"
gem "metanorma-mko", github: "metanorma/metanorma-mko", branch: "main"

begin
  eval_gemfile("Gemfile.devel")
rescue StandardError
  nil
end

gem "debug"
gem "equivalent-xml"
#gem "metanorma-iho"
#gem "metanorma-iso", ">= 3.2.0"
gem "mnconvert"
gem "pry"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rspec-command", "~> 1.0"
gem "rubocop", "~> 1"
gem "rubocop-performance"
gem "sassc-embedded", "~> 1"
gem "simplecov", "~> 0.15"
