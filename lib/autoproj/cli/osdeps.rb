require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class OSDeps < InspectionTool
            def run(user_selection, options = Hash.new)
                initialize_and_load
                _, osdep_packages, resolved_selection, _ =
                    finalize_setup(user_selection,
                                   ignore_non_imported_packages: true)

                ws.install_os_packages(
                    osdep_packages,
                    install_only: !options[:update])
            end
        end
    end
end

