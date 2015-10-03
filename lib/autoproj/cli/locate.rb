require 'autoproj'
require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Locate < Base
            class NotFound < RuntimeError; end
            class AmbiguousSelection < RuntimeError; end

            attr_reader :installation_manifest

            def initialize(ws = nil)
                super
                self.ws.load_config

                path = InstallationManifest.path_for_root(self.ws.root_dir)
                if !File.file?(path)
                    raise ConfigError, "the installation manifest is not present, please run autoproj envsh to generate it"
                end

                @installation_manifest = Autoproj::InstallationManifest.new(path)
                installation_manifest.load
            end

            def validate_options(selected, options)
                selected, options = super
                return selected.first, options
            end

            def result_value(pkg, options)
                if options[:build]
                    if pkg.builddir
                        pkg.builddir
                    else
                        raise ConfigError, "#{pkg.name} does not have a build directory"
                    end
                else
                    pkg.srcdir
                end
            end

            def run(selection, options = Hash.new)
                if !selection
                    if options[:build]
                        puts ws.prefix_dir
                    else
                        puts ws.root_dir
                    end
                    return
                end

                if File.directory?(selection)
                    selection = File.expand_path(selection)
                end

                selection_rx = Regexp.new(Regexp.quote(selection))
                candidates = []
                installation_manifest.each do |pkg|
                    name = pkg.name
                    if name == selection || pkg.srcdir == selection
                        puts result_value(pkg, options)
                        return
                    elsif name =~ selection_rx || selection.start_with?(pkg.srcdir)
                        candidates << pkg
                    end
                end

                if candidates.empty?
                    # Try harder. Match directory prefixes
                    directories = selection.split('/')
                    rx = directories.
                        map { |d| "#{Regexp.quote(d)}\\w*" }.
                        join("/")
                    rx = Regexp.new(rx)

                    rx_strict = directories[0..-2].
                        map { |d| "#{Regexp.quote(d)}\\w*" }.
                        join("/")
                    rx_strict = Regexp.new("#{rx_strict}/#{Regexp.quote(directories.last)}$")

                    candidates_strict = []
                    installation_manifest.each do |pkg|
                        name = pkg.name
                        if name =~ rx
                            candidates << pkg
                        end
                        if name =~ rx_strict
                            candidates_strict << pkg
                        end
                    end

                    if candidates.size > 1 && candidates_strict.size == 1
                        candidates = candidates_strict
                    end
                end

                if candidates.size > 1
                    # If there is more than one candidate, check if there are some that are not
                    # present on disk
                    present = candidates.find_all { |pkg| File.directory?(pkg.srcdir) }
                    if present.size == 1
                        candidates = present
                    end
                end

                if candidates.empty?
                    raise ArgumentError, "cannot find #{selection} in the current autoproj installation"
                elsif candidates.size > 1
                    raise ArgumentError, "multiple packages match #{selection} in the current autoproj installation: #{candidates.map(&:name).sort.join(", ")}"
                else
                    puts result_value(candidates.first, options)
                end
            end
        end
    end
end

