# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'autoproj/version'

Gem::Specification.new do |s|
    s.name = "autoproj"
    s.version = Autoproj::VERSION
    s.authors = ["Sylvain Joyeux"]
    s.email = "sylvain.joyeux@m4x.org"
    s.summary = "Easy installation and management of sets of software packages"
    s.description = "autoproj is a manager for sets of software packages. It allows the user to import and build packages from source, still using the underlying distribution's native package manager for software that is available on it."
    s.homepage = "http://rock-robotics.org"
    s.licenses = ["BSD"]

    s.required_ruby_version = ">= 2.0.0"
    s.bindir = 'bin'
    s.executables = ['autoproj', 'aup', 'amake', 'alocate']
    s.require_paths = ["lib"]
    s.extensions = []
    s.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

    s.add_runtime_dependency "autobuild", ">= 1.10.0.a"
    s.add_runtime_dependency "utilrb", ">= 3.0"
    s.add_runtime_dependency "thor", '~> 0.19.0', '>= 0.19.1'
    s.add_runtime_dependency 'concurrent-ruby'
    s.add_runtime_dependency 'tty-color', '~> 0.3.0', '>= 0.3.0'
    s.add_development_dependency "flexmock", ">= 2.0.0"
    s.add_development_dependency "minitest", ">= 5.0", "~> 5.0"
    s.add_development_dependency "fakefs"
    s.add_development_dependency "simplecov"
end

