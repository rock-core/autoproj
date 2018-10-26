require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Test < InspectionTool
            def enable(user_selection, options = {})
                if user_selection.empty?
                    ws.load_config
                    ws.config.utility_enable_all('test')
                else
                    initialize_and_load
                    selection, = finalize_setup(
                        user_selection,
                        recursive: options[:deps],
                        non_imported_packages: :return
                    )
                    ws.config.utility_enable('test', *selection)
                end
                ws.config.save
            end

            def disable(user_selection, options = {})
                if user_selection.empty?
                    ws.load_config
                    ws.config.utility_disable_all('test')
                else
                    initialize_and_load
                    selection, = finalize_setup(
                        user_selection,
                        recursive: options[:deps],
                        non_imported_packages: :return
                    )
                    ws.config.utility_disable('test', *selection)
                end
                ws.config.save
            end

            def list(user_selection, options = {})
                initialize_and_load
                resolved_selection, = finalize_setup(
                    user_selection,
                    recursive: options[:deps],
                    non_imported_packages: :return
                )

                lines = []
                resolved_selection.each do |pkg_name|
                    pkg = ws.manifest.find_package_definition(pkg_name).autobuild
                    lines << [pkg.name, pkg.test_utility.enabled?, pkg.test_utility.available?]
                end
                lines = lines.sort_by { |name, _| name }
                w     = lines.map { |name, _| name.length }.max
                out_format = "%-#{w}s %-7s %-9s"
                puts format(out_format, 'Package Name', 'Enabled', 'Available')
                lines.each do |name, enabled, available|
                    puts(format(out_format, name, (!!enabled).to_s, (!!available).to_s))
                end
            end

            def run(user_selection, deps: true)
                initialize_and_load
                packages, =
                    finalize_setup(user_selection, recursive: deps)
                packages.each do |pkg|
                    ws.manifest.find_autobuild_package(pkg).disable_phases('import', 'prepare', 'install')
                end
                Autobuild.apply(packages, 'autoproj-test', ['test'])
            end
        end
    end
end
