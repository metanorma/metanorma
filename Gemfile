Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}" }

gemspec

gem "metanorma-standoc", git: "https://github.com/metanorma/metanorma-standoc", branch: "feature/move-fontist-logic-to-metanorma-gem"

if File.exist? 'Gemfile.devel'
  eval File.read('Gemfile.devel'), nil, 'Gemfile.devel' # rubocop:disable Security/Eval
end
