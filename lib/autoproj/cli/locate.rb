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

                @installation_manifest = Autoproj::InstallationManifest.new(self.ws.root_dir)
                if !File.file?(installation_manifest.default_manifest_path)
                    raise ConfigError, "the installation manifest is not present, please run autoproj envsh to generate it"
                end
                installation_manifest.load
            end

            def validate_options(selected, options)
                selected, options = super
                return selected.first, options
            end

            def run(selection, options = Hash.new)
                if !selection
                    puts ws.root_dir
                    return
                end

                selection_rx = Regexp.new(Regexp.quote(selection))
                candidates = []
                installation_manifest.each do |pkg|
                    name = pkg.name
                    srcdir = pkg.srcdir
                    if name == selection
                        puts srcdir
                        exit(0)
                    elsif name =~ selection_rx
                        candidates << srcdir
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
                        srcdir = pkg.srcdir
                        if name =~ rx
                            candidates << srcdir
                        end
                        if name =~ rx_strict
                            candidates_strict << srcdir
                        end
                    end

                    if candidates.size > 1 && candidates_strict.size == 1
                        candidates = candidates_strict
                    end
                end

                if candidates.size > 1
                    # If there is more than one candidate, check if there are some that are not
                    # present on disk
                    present = candidates.find_all { |dir| File.directory?(dir) }
                    if present.size == 1
                        candidates = present
                    end
                end

                if candidates.empty?
                    raise NotFound, "cannot find #{selection} in the current autoproj installation"
                elsif candidates.size > 1
                    raise AmbiguousSelection, "multiple packages match #{selection} in the current autoproj installation: #{candidates.join(", ")}"
                else
                    puts candidates.first
                end
            end
        end
    end
end

