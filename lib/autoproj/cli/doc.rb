require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Doc < InspectionTool
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
