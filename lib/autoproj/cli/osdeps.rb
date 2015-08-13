require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class OSDeps < InspectionTool
            def validate_options(package_names, options = Hash.new)
                package_names, options = super

                initialize_and_load
                if package_names.empty?
                    package_names = ws.manifest.default_packages(false)
                end

                return package_names, options
            end

            def run(user_selection, options = Hash.new)
                initialize_and_load
                _, osdep_packages, resolved_selection, _ =
                    finalize_setup(user_selection,
                                   ignore_non_imported_packages: true)

                ws.osdeps.install(
                    osdep_packages,
                    install_only: !options[:update])
            end
        end
    end
end

