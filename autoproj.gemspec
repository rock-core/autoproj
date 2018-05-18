# coding: utf-8
require 'rbconfig'

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'autoproj/version'

Gem::Specification.new do |s|
    s.name = "autoproj"
    # The envvar is here for the benefit of tests that require to create gems
    # with a "fake" version
    s.version = ENV['__AUTOPROJ_TEST_FAKE_VERSION'] || Autoproj::VERSION
    s.authors = ["Sylvain Joyeux"]
    s.email = "sylvain.joyeux@m4x.org"
    s.summary = "Easy installation and management of sets of software packages"
    s.description = "autoproj is a manager for sets of software packages. It allows the user to import and build packages from source, still using the underlying distribution's native package manager for software that is available on it."
    s.homepage = "http://rock-robotics.org"
    s.licenses = ["BSD"]

    s.required_ruby_version = '>= 2.1.0'
    s.bindir = 'bin'
    s.executables = ['autoproj', 'aup', 'amake', 'alocate', 'alog']
    s.require_paths = ["lib"]
    s.extensions = []
    s.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

    s.add_runtime_dependency "bundler"
    s.add_runtime_dependency "autobuild", ">= 1.14.0"
    s.add_runtime_dependency "backports", '~> 3.0'
    s.add_runtime_dependency "utilrb", '~> 3.0.0', ">= 3.0.0"
    s.add_runtime_dependency "thor", '~> 0.20.0'
    s.add_runtime_dependency 'concurrent-ruby', '~> 1.0.0', '>= 1.0.0'
    s.add_runtime_dependency 'tty-color', '~> 0.4.0', '>= 0.4.0'
    s.add_runtime_dependency 'tty-prompt', '~> 0.15.0'
    s.add_runtime_dependency 'tty-spinner', '~> 0.8.0'
    s.add_runtime_dependency 'rb-inotify' if RbConfig::CONFIG['target_os'] =~ /linux/
    s.add_runtime_dependency 'xdg'
    s.add_development_dependency "flexmock", '~> 2.0', ">= 2.0.0"
    s.add_development_dependency "minitest", "~> 5.0", ">= 5.0"
    s.add_development_dependency "simplecov"
    s.add_development_dependency "aruba"
end

