require 'autoproj/cli/base'

module Autoproj
    module CLI
        # Base class for CLI tools that do not change the state of the installed
        # system
        class InspectionTool < Base
            def initialize_and_load(mainline: nil)
                Autoproj.silent do
                    ws.setup
                    if mainline == 'mainline' || mainline == 'true'
                        mainline = true
                    end
                    ws.load_package_sets(mainline: mainline)
                    ws.config.save
                    ws.setup_all_package_directories
                end
            end

            # Finish loading the package information
            #
            # @param [Array<String>] packages the list of package names
            # @param [Symbol] non_imported_packages whether packages that are
            #   not yet imported should be ignored (:ignore) or returned
            #   (:return). 
            # @option options recursive (true) whether the package resolution
            #   should return the package(s) and their dependencies
            #
            # @return [(Array<String>,PackageSelection,Boolean)] the list of
            #   selected packages, the PackageSelection representing the
            #   selection resolution itself, and a flag telling whether some of
            #   the arguments were pointing within the configuration area
            def finalize_setup(packages = [], non_imported_packages: :ignore, recursive: true)
                Autoproj.silent do
                    packages, config_selected = normalize_command_line_package_selection(packages)
                    # Call resolve_user_selection once to auto-add packages, so
                    # that they're available to e.g. overrides.rb
                    resolve_user_selection(packages)
                    ws.finalize_package_setup
                    source_packages, osdep_packages, resolved_selection =
                        resolve_selection(packages, recursive: recursive, non_imported_packages: non_imported_packages)
                    ws.finalize_setup
                    ws.export_installation_manifest
                    return source_packages, osdep_packages, resolved_selection, config_selected
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
