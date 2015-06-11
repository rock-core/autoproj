require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Test < InspectionTool
            def enable(user_selection, options = Hash.new)
                if user_selection.empty?
                    ws.config.utility_enable_all('test')
                else
                    initialize_and_load
                    selection, _ = finalize_setup(
                        user_selection,
                        recursive: options[:deps],
                        ignore_non_imported_packages: true)
                    ws.config.utility_enable('test', *selection)
                end
                ws.config.save
            end

            def disable(user_selection, options = Hash.new)
                if user_selection.empty?
                    ws.config.utility_disable_all('test')
                else
                    initialize_and_load
                    selection, _ = finaliez_setup(
                        user_selection,
                        recursive: options[:deps],
                        ignore_non_imported_packages: true)
                    ws.config.utility_disable('test', *selection)
                end
                ws.config.save
            end

            def list(user_selection, options = Hash.new)
                initialize_and_load
                resolved_selection, _ = finalize_setup(
                    user_selection,
                    recursive: options[:dep],
                    ignore_non_imported_packages: true)

                lines = Array.new
                resolved_selection.each do |pkg_name|
                    pkg = ws.manifest.find_package(pkg_name).autobuild
                    lines << [pkg.name, pkg.test_utility.enabled?, pkg.test_utility.available?]
                end
                lines = lines.sort_by { |name, _| name }
                w     = lines.map { |name, _| name.length }.max
                format = "%-#{w}s %-7s %-9s"
                puts format % ["Package Name", "Enabled", "Available"]
                lines.each do |name, enabled, available|
                    puts(format % [name, (!!enabled).to_s, (!!available).to_s])
                end
            end

            def run(user_selection, options = Hash.new)
                initialize_and_load
                packages, _ = finalize_setup(user_selection)

                packages.each do |pkg|
                    Autobuild::Package[pkg].disable_phases('import', 'prepare', 'install')
                end
                Autobuild.apply(packages, "autoproj-test", ['test'])
            end
        end
    end
end

