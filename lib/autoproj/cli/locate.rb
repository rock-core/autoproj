require 'autoproj/cli/base'

module Autoproj
    module CLI
        # Deal with locating a package source or build directory in an existing
        # workspace
        #
        # It is based on a installation manifest file, a YAML file generated to
        # list that information and thus avoid loading the Autoproj
        # configuration (which takes fairly long).
        class Locate < Base
            class NotFound < RuntimeError; end
            class AmbiguousSelection < RuntimeError; end

            attr_reader :installation_manifest

            # Create the locate CLI interface
            #
            # @param [Workspace] ws the workspace we're working on
            # @param [InstallationManifest] installation_manifest the manifest.
            def initialize(ws = Workspace.default,
                           installation_manifest: load_installation_manifest(ws))
                super(ws)
                @installation_manifest = installation_manifest
            end

            # Load the installation manifest
            def load_installation_manifest(ws = self.ws)
                Autoproj::InstallationManifest.from_workspace_root(ws.root_dir)
            end

            def validate_options(selected, options)
                if selected.size > 1
                    raise ArgumentError, "more than one package selection string given"
                end
                selected, options = super
                return selected.first, options
            end

            def result_value(pkg, build: false)
                if build
                    if pkg.builddir
                        pkg.builddir
                    else
                        raise ArgumentError, "#{pkg.name} does not have a build directory"
                    end
                else
                    pkg.srcdir
                end
            end

            # Find a package set that matches a given selection
            #
            # @param [String] selection a string that is matched against the
            #   package set name and its various directories. Directories are
            #   matched against the full path and must end with /
            # @return [PackageSet,nil]
            def find_package_set(selection)
                installation_manifest.each_package_set.find do |pkg_set|
                    name = pkg_set.name
                    name == selection ||
                        selection.start_with?("#{pkg_set.raw_local_dir}/") ||
                        selection.start_with?("#{pkg_set.user_local_dir}/")
                end
            end

            def find_packages(selection)
                selection_rx = Regexp.new(Regexp.quote(selection))
                candidates = []
                installation_manifest.each_package do |pkg|
                    name = pkg.name
                    if name == selection || selection.start_with?("#{pkg.srcdir}/")
                        return [pkg]
                    elsif pkg.builddir && selection.start_with?("#{pkg.builddir}/")
                        return [pkg]
                    elsif name =~ selection_rx
                        candidates << pkg
                    end
                end
                return candidates
            end

            def find_packages_with_directory_shortnames(selection)
                *directories, basename = *selection.split('/')
                dirname_rx = directories.
                    map { |d| "#{Regexp.quote(d)}\\w*" }.
                    join("/")

                rx        = Regexp.new("#{dirname_rx}/#{Regexp.quote(basename)}")
                rx_strict = Regexp.new("#{dirname_rx}/#{Regexp.quote(basename)}$")

                candidates = []
                candidates_strict = []
                installation_manifest.each_package do |pkg|
                    name = pkg.name
                    if name =~ rx
                        candidates << pkg
                    end
                    if name =~ rx_strict
                        candidates_strict << pkg
                    end
                end

                if candidates.size > 1 && candidates_strict.size == 1
                    candidates_strict
                else
                    candidates
                end
            end

            def run(selection, build: false)
                if selection && File.directory?(selection)
                    selection = "#{File.expand_path(selection)}/"
                end
                puts location_of(selection, build: build)
            end

            def location_of(selection, build: false)
                if !selection
                    if build
                        return ws.prefix_dir
                    else
                        return ws.root_dir
                    end
                elsif pkg_set = find_package_set(selection)
                    return pkg_set.user_local_dir
                end

                matching_packages = find_packages(selection)
                if matching_packages.empty?
                    matching_packages = find_packages_with_directory_shortnames(selection)
                end

                if matching_packages.size > 1
                    # If there is more than one candidate, check if there are some that are not
                    # present on disk
                    present = matching_packages.find_all { |pkg| File.directory?(pkg.srcdir) }
                    if present.size == 1
                        matching_packages = present
                    end
                end

                if matching_packages.empty?
                    raise NotFound, "cannot find '#{selection}' in the current autoproj installation"
                elsif matching_packages.size > 1
                    raise AmbiguousSelection, "multiple packages match '#{selection}' in the current autoproj installation: #{matching_packages.map(&:name).sort.join(", ")}"
                else
                    return result_value(matching_packages.first, build: build)
                end
            end
        end
    end
end

