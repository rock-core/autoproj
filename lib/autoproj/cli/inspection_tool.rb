require 'autoproj/cli/base'

module Autoproj
    module CLI
        # Base class for CLI tools that do not change the state of the installed
        # system
        class InspectionTool < Base
            def initialize(ws = nil)
                super(ws)
                initialize_and_load
            end

            def initialize_and_load
                Autoproj.silent do
                    ws.setup
                    ws.load_package_sets
                    ws.setup_all_package_directories
                end
            end

            # Finish loading the package information
            #
            # @param [Array<String>] packages the list of package names
            # @option options ignore_non_imported_packages (true) whether
            #   packages that are not present on disk should be ignored (true in
            #   most cases)
            # @option options recursive (true) whether the package resolution
            #   should return the package(s) and their dependencies
            #
            # @return [(Array<String>,PackageSelection,Boolean)] the list of
            #   selected packages, the PackageSelection representing the
            #   selection resolution itself, and a flag telling whether some of
            #   the arguments were pointing within the configuration area
            def finalize_setup(packages, options = Hash.new)
                options = Kernel.validate_options options,
                    ignore_non_imported_packages: true,
                    recursive: true

                Autoproj.silent do
                    packages, config_selected = normalize_command_line_package_selection(packages)
                    selected_packages, resolved_selection = resolve_selection(ws.manifest, packages, options)
                    ws.finalize_package_setup
                    ws.export_installation_manifest
                    return selected_packages, resolved_selection, config_selected
                end
            end

            def load_all_available_package_manifests
                # Load the manifest for packages that are already present on the
                # file system
                ws.manifest.packages.each_value do |pkg|
                    if File.directory?(pkg.autobuild.srcdir)
                        begin
                            ws.manifest.load_package_manifest(pkg.autobuild.name)
                        rescue Interrupt
                            raise
                        rescue Exception => e
                            Autoproj.warn "cannot load package manifest for #{pkg.autobuild.name}: #{e.message}"
                        end
                    end
                end
            end
        end
    end
end
