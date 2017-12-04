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
            attr_reader :packages
            attr_reader :package_sets
            
            class NotFound < CLIException; end
            class NoSuchDir < CLIException; end

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

            def validate_options(selections, options = Hash.new)
                selections, options = super
                mode = if options.delete(:build)
                           :build_dir
                       elsif options.delete(:prefix)
                           :prefix_dir
                       elsif log_type = options[:log]
                           if log_type == 'log'
                               options.delete(:log)
                           end
                           :log
                       else
                           :source_dir
                       end
                options[:mode] ||= mode
                if selections.empty?
                    selections << ws.root_dir
                end
                return selections, options
            end

            RESOLUTION_MODES = [:source_dir, :build_dir, :prefix_dir, :log]

            def run(selections, cache: !!packages, mode: :source_dir, log: nil)
                if !RESOLUTION_MODES.include?(mode)
                    raise ArgumentError, "'#{mode}' was expected to be one of #{RESOLUTION_MODES}"
                elsif !cache
                    initialize_from_workspace
                end

                selections.each do |string|
                    if File.directory?(string)
                        string = "#{File.expand_path(string)}/"
                    end
                    if mode == :source_dir
                        puts source_dir_of(string)
                    elsif mode == :build_dir
                        puts build_dir_of(string)
                    elsif mode == :prefix_dir
                        puts prefix_dir_of(string)
                    elsif mode == :log
                        if all_logs = (log == 'all')
                            log = nil
                        end
                        result = logs_of(string, log: log)
                        if (result.size == 1) || all_logs
                            result.each { |p| puts p }
                        elsif result.size > 1
                            puts select_log_file(result)
                        elsif result.empty?
                            raise NotFound, "no logs found for #{string}"
                        end
                    end
                end
            end

            # Resolve the package that matches a given selection
            #
            # @return [PackageDefinition]
            # @raise [CLIInvalidArguments] if nothing matches
            # @raise [AmbiguousSelection] if the selection is ambiguous
            def resolve_package(selection)
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
                    raise CLIInvalidArguments, "cannot find '#{selection}' in the current autoproj installation"
                elsif matching_packages.size > 1
                    raise CLIAmbiguousArguments, "multiple packages match '#{selection}' in the current autoproj installation: #{matching_packages.map(&:name).sort.join(", ")}"
                else
                    return matching_packages.first
                end
            end

            # Tests whether 'selection' points to one of the workspace's root
            # directories
            def workspace_dir?(selection)
                selection == "#{ws.root_dir}/" || selection == "#{ws.prefix_dir}/"
            end

            # Returns the source directory for a given selection
            def source_dir_of(selection)
                if workspace_dir?(selection)
                    ws.root_dir
                elsif pkg_set = find_package_set(selection)
                    pkg_set.user_local_dir
                else
                    resolve_package(selection).srcdir
                end
            end

            # Returns the prefix directory for a given selection
            #
            # @raise [NoSuchDir] if the selection points to a package set
            def prefix_dir_of(selection)
                if workspace_dir?(selection)
                    ws.prefix_dir
                elsif find_package_set(selection)
                    raise NoSuchDir, "#{selection} is a package set, and package sets do not have prefixes"
                else
                    resolve_package(selection).prefix
                end
            end

            # Returns the build directory for a given selection
            #
            # @raise [NoSuchDir] if the selection points to a package set,
            #   or to a package that has no build directory
            def build_dir_of(selection)
                if workspace_dir?(selection)
                    raise NoSuchDir, "#{selection} points to the workspace itself, which has no build dir"
                elsif find_package_set(selection)
                    raise NoSuchDir, "#{selection} is a package set, and package sets do not have build directories"
                else
                    pkg = resolve_package(selection)
                    if pkg.respond_to?(:builddir) && pkg.builddir
                        pkg.builddir
                    else
                        raise NoSuchDir, "#{selection} resolves to the package #{pkg.name}, which does not have a build directory"
                    end
                end
            end

            # Resolve logs available for what points to the given selection
            #
            # The workspace is resolved as the main configuration
            #
            # If 'log' is nil and multiple logs are available, 
            def logs_of(selection, log: nil)
                if workspace_dir?(selection) || (pkg_set = find_package_set(selection))
                    if log && log != 'import'
                        return []
                    end
                    name = if pkg_set then pkg_set.name
                           else "autoproj main configuration"
                           end

                    import_log = File.join(ws.log_dir, "#{name}-import.log")
                    if File.file?(import_log)
                        return [import_log]
                    else return []
                    end
                else
                    pkg = resolve_package(selection)
                    Dir.enum_for(:glob, File.join(pkg.logdir, "#{pkg.name}-#{log || '*'}.log")).to_a
                end
            end

            # Interactively select a log file among a list
            def select_log_file(log_files)
                require 'tty/prompt'

                log_files = log_files.map do |path|
                    [path, File.stat(path).mtime]
                end.sort_by(&:last).reverse

                choices = Hash.new
                log_files.each do |path, mtime|
                    if path =~ /-(\w+)\.log/
                        choices["(#{mtime}) #{$1}"] = path
                    else
                        choices["(#{mtime}) #{path}"] = path
                    end
                end

                prompt = TTY::Prompt.new
                prompt.select("Select the log file", choices)
            end
        end
    end
end

