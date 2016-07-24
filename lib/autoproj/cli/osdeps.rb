require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class OSDeps < InspectionTool
            def run(user_selection, options = Hash.new)
                initialize_and_load
                _, osdep_packages, resolved_selection, _ =
                    finalize_setup(user_selection,
                                   ignore_non_imported_packages: true)

                options = Kernel.validate_options options,
                    update: true,
                    shell_helpers: ws.config.shell_helpers?
                ws.install_os_packages(
                    osdep_packages,
                    run_package_managers_without_packages: true,
                    install_only: !options[:update])
                ws.export_env_sh(shell_helpers: options[:shell_helpers])
            end
        end
    end
end

