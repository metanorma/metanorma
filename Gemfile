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
gem "canon", "~> 0.3.122"
# lutaml-store 0.3.10 shipped conflict markers (lutaml-store#31); 0.3.11 fixes
gem "lutaml-store", "~> 0.3.11"
#gem "metanorma-iho"
#gem "metanorma-iso", ">= 3.2.0"
# Floor fontist at the variable-font indexing fix (fontist#531/#532):
# anything below 3.0.31 misses freshly installed variable fonts on
# locations lookups ("Fira Code" MissingFontError, metanorma-iho#563).
gem "fontist", "~> 3.0.32"
gem "mnconvert"
gem "pry"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rspec-command", "~> 1.0"
gem "rubocop", "~> 1"
gem "rubocop-performance"
gem "sassc-embedded", "~> 1"
gem "simplecov", "~> 0.15"
