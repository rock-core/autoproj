Gem::Specification.new do |s|
  s.name = %q{rubotics-orocos}
  s.version = "1.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Sylvain Joyeux"]
  s.date = %q{2009-09-18}
  s.description = %q{Installs all Ruby dependencies for the Rubotics Orocos profile}
  s.summary = %q{Rubotics is a project that provides different toolchains
for robotics development using Ruby and C++. This file installs the Ruby
dependencies for the Orocos profile.}
  s.email = %q{rubotics@rubyforge.org}
  s.files = []
  s.has_rdoc = false
  s.homepage = %q{http://rubotics.rubyforge.org/}
  s.require_paths = ["."]
  s.rubyforge_project = %q{}
  s.rubygems_version = %q{1.2.0}
  s.rubyforge_project = "rubotics"

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if current_version >= 3 then
        s.add_runtime_dependency(%q<hoe>,       ["< 2.0"])
        s.add_runtime_dependency(%q<facets>,    [">= 2.6"])
        s.add_runtime_dependency(%q<nokogiri>,  [">= 1.3"])
        s.add_runtime_dependency(%q<autobuild>, [">= 1.2.15"])
        s.add_runtime_dependency(%q<rdoc>,      [">= 2.0"])
        s.add_runtime_dependency(%q<webgen>,    [">= 0.5.9"])
        s.add_runtime_dependency(%q<coderay>,   [">= 0.8"])
    else
        s.add_dependency(%q<hoe>,       ["< 2.0"])
        s.add_dependency(%q<facets>,    [">= 2.6"])
        s.add_dependency(%q<nokogiri>,  [">= 1.3"])
        s.add_dependency(%q<autobuild>, [">= 1.2.15"])
        s.add_dependency(%q<rdoc>,      [">= 2.0"])
        s.add_dependency(%q<webgen>,    [">= 0.5.9"])
        s.add_dependency(%q<coderay>,   [">= 0.8"])
    end
  else
  end
end
