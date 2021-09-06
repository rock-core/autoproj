require "autoproj/cli/inspection_tool"

module Autoproj
    module CLI
        class OSDeps < InspectionTool
            def run(user_selection, update: true, **options)
                initialize_and_load
                if options[:system_info]
                    os_names, os_versions = ws.os_package_resolver.operating_system
                    os_package_manager_names = OSPackageResolver::OS_PACKAGE_MANAGERS.values
                    os_indep_managers = ws.os_package_installer.package_managers
                                          .each_key.find_all do |name, manager|
                        !os_package_manager_names.include?(name)
                    end
                    puts "OS Names:    #{(os_names - ['default']).join(', ')}"
                    puts "OS Versions: #{(os_versions - ['default']).join(', ')}"
                    puts "OS Package Manager: #{ws.os_package_resolver.os_package_manager}"
                    puts "Available Package Managers: #{os_indep_managers.sort.join(', ')}"
                    return
                end

                _, osdep_packages, resolved_selection, =
                    finalize_setup(user_selection)

                shell_helpers = options.fetch(:shell_helpers, ws.config.shell_helpers?)

                ws.install_os_repositories
                ws.install_os_packages(
                    osdep_packages,
                    run_package_managers_without_packages: true,
                    install_only: !update
                )
                export_env_sh(shell_helpers: shell_helpers)
                Main.run_post_command_hook(:update, ws, source_packages: [],
                                                        osdep_packages: osdep_packages)
            end
        end
    end
end
