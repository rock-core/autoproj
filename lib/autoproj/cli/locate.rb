require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        # Deal with locating a package source or build directory in an existing
        # workspace
        #
        # It is based on a installation manifest file, a YAML file generated to
        # list that information and thus avoid loading the Autoproj
        # configuration (which takes fairly long).
        class Locate < InspectionTool
            class NotFound < RuntimeError; end
            class AmbiguousSelection < RuntimeError; end

            attr_reader :packages
            attr_reader :package_sets

            # Create the locate CLI interface
            #
            # @param [Workspace] ws the workspace we're working on
            # @param [InstallationManifest,nil] installation_manifest the
            #     manifest. If nil, loads the whole autoproj configuration and
            #     rebuilds the manifest
            def initialize(ws = Workspace.default, installation_manifest: try_loading_installation_manifest(ws))
                super(ws)
                ws.load_config

                if installation_manifest
                    update_from_installation_manifest(installation_manifest)
                end
            end

            def update_from_installation_manifest(installation_manifest)
                @packages = installation_manifest.each_package.to_a
                @package_sets = installation_manifest.each_package_set.to_a
            end

            # Load the installation manifest
            def try_loading_installation_manifest(ws = self.ws)
                Autoproj::InstallationManifest.from_workspace_root(ws.root_dir)
            rescue ConfigError
            end

            # Find a package set that matches a given selection
            #
            # @param [String] selection a string that is matched against the
            #   package set name and its various directories. Directories are
            #   matched against the full path and must end with /
            # @return [PackageSet,nil]
            def find_package_set(selection)
                package_sets.find do |pkg_set|
                    name = pkg_set.name
                    name == selection ||
                        selection.start_with?("#{pkg_set.raw_local_dir}/") ||
                        selection.start_with?("#{pkg_set.user_local_dir}/")
                end
            end

            def find_packages(selection)
                selection_rx = Regexp.new(Regexp.quote(selection))
                candidates = []
                packages.each do |pkg|
                    name = pkg.name
                    if name == selection || selection.start_with?("#{pkg.srcdir}/")
                        return [pkg]
                    elsif pkg.respond_to?(:builddir) && pkg.builddir && selection.start_with?("#{pkg.builddir}/")
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
                packages.each do |pkg|
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

            def initialize_from_workspace
                initialize_and_load
                finalize_setup # this exports the manifest

                @packages = ws.manifest.each_autobuild_package.to_a
                @package_sets = ws.manifest.each_package_set.to_a
            end

            def run(selections, cache: !!packages, build: false, prefix: false)
                if !cache
                    initialize_from_workspace
                end

                if selections.empty?
                    if prefix || build
                        puts ws.prefix_dir
                    else
                        puts ws.root_dir
                    end
                end

                selections.each do |string|
                    if File.directory?(string)
                        string = "#{File.expand_path(string)}/"
                    end
                    puts location_of(string, build: build, prefix: prefix)
                end
            end

            def location_of(selection, prefix: false, build: false)
                if pkg_set = find_package_set(selection)
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
                    pkg = matching_packages.first
                    if prefix
                        pkg.prefix
                    elsif build
                        if pkg.respond_to?(:builddir) && pkg.builddir
                            pkg.builddir
                        else
                            raise ArgumentError, "#{pkg.name} does not have a build directory"
                        end
                    else
                        pkg.srcdir
                    end
                end
            end
        end
    end
end

