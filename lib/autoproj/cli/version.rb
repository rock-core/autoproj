require "autoproj/cli/base"
require "rubygems"

module Autoproj
    module CLI
        class Version < Base
            # List the version of autoproj and optionally include
            # the installed dependencies with information about the requirement
            # and the actual used version
            def run(args, options = Hash.new)
                puts "autoproj version: #{Autoproj::VERSION}"
                return unless options[:deps]

                dependency = Gem::Deprecate.skip_during do
                    Gem::Dependency.new "autoproj", Autoproj::VERSION
                end
                autoproj_spec = dependency.matching_specs
                return if autoproj_spec.empty?

                installed_deps = collect_dependencies(dependency)
                puts "    specified dependencies:"
                autoproj_spec.first.dependencies.each do |dep|
                    puts "        #{dep}: #{installed_deps[dep.name] || 'n/a'}"
                    installed_deps.delete(dep.name)
                end
                puts "    implicit dependencies:"
                installed_deps.keys.sort.each do |name|
                    unless name == "autoproj"
                        puts "        #{name}: #{installed_deps[name]}"
                    end
                end
            end

            # Collect the dependencies of a given dependency
            # @param [Gem::Dependency] dependency a gem depencency
            # @param [Array<Gem::Dependency] list of already known dependencies
            #
            # @return [Array<Gem::Dependency>] all known dependencies
            def collect_dependencies(dependency, known_dependencies: {})
                dep_spec = dependency.matching_specs
                return known_dependencies if dep_spec.empty?

                dep_spec = dep_spec.first
                known_dependencies[dep_spec.name] = dep_spec.version
                dep_spec.dependencies.each do |dep|
                    unless known_dependencies.has_key?(dep.name)
                        collect_dependencies(dep, known_dependencies: known_dependencies)
                    end
                end
                known_dependencies
            end
        end
    end
end
