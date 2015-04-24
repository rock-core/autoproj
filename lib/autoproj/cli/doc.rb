require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Doc < InspectionTool
            def run(selected_packages, options = Hash.new)
                options = Kernel.validate_options options,
                    with_deps: true

                selected_packages, _ =
                    normalize_command_line_package_selection(selected_packages)
                package_names, _ = resolve_selection(selected_packages, recursive: options[:with_deps])

                packages.each do |pkg|
                    ws.manifest.find_autobuild_package(pkg).disable_phases('import', 'prepare', 'install')
                end
                Autobuild.apply(packages, "autoproj-doc", ['doc'])
            end
        end
    end
end
