source "https://rubygems.org"

gem "autobuild", git: "https://github.com/rock-core/autobuild", branch: "master"
gem "rubygems-server" unless RUBY_VERSION < "3"

group :dev do
    gem "rubocop", "~> 1.28.0"
    gem "rubocop-rock"

    if RUBY_VERSION > "3.0"
        gem "aruba", "~> 2.3.0"
    else
        gem "aruba", "~> 2.1.0"
    end

    gem "flexmock"
    gem "minitest", ">= 5.0"
    gem "simplecov"
    gem "timecop"
    gem "tty-cursor"
end

group :vscode do
    gem "debase", ">= 0.2.2.beta10"
    gem "pry"
    gem "pry-byebug"
    gem "ruby-debug-ide", ">= 0.6.0"
    gem "solargraph"
end

gemspec
