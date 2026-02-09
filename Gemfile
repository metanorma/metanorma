Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}" }

gemspec

begin
  eval_gemfile("Gemfile.devel")
rescue StandardError
  nil
end

gem "debug"
gem "equivalent-xml"
#gem "metanorma-iho"
gem "metanorma-iso", ">= 3.2.0"
gem "mnconvert"
gem "pry"
gem "rake", "~> 13.0"
gem "rspec", "~> 3.0"
gem "rspec-command", "~> 1.0"
gem "rubocop", "~> 1"
gem "rubocop-performance"
gem "sassc-embedded", "~> 1"
gem "simplecov", "~> 0.15"
