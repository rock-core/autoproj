source "https://rubygems.org"

gem "autobuild", git: "https://github.com/rock-core/autobuild", branch: "master"
gem "rubygems-server" unless RUBY_VERSION < "3"

group :dev do
    gem "rubocop", "~> 1.28.0"
    gem "rubocop-rock"
end

group :vscode do
    gem "debug"
    gem "pry"
    gem "pry-byebug"
    gem "ruby-lsp"
end

gemspec
