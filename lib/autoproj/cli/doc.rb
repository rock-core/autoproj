require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Doc < InspectionTool
            def validate_options(packages, options)
                packages, options = super
                if options[:no_deps_shortcut]
                    options[:deps] = false
                end
                return packages, options
            end

            def run(user_selection, deps: true)
                initialize_and_load
                packages, _ =
                    finalize_setup(user_selection, recursive: deps)
                packages.each do |pkg|
                    ws.manifest.find_autobuild_package(pkg).disable_phases('import', 'prepare', 'install')
                end
                Autobuild.apply(packages, "autoproj-doc", ['doc'])
            end
        end
    end
end
