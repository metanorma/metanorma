Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}" }

gemspec

if File.exist? 'Gemfile.devel'
  eval File.read('Gemfile.devel'), nil, 'Gemfile.devel' # rubocop:disable Security/Eval
end

gem "byebug", "~> 11.1"
gem "metanorma-standoc",
  git: 'git@github.com:metanorma/metanorma-standoc.git',
  branch: 'feature/expose-to_ncname-method-publically'
