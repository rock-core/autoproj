require "autoproj/cli/inspection_tool"
module Autoproj
    module CLI
        # Interface to patch/unpatch a package
        class Patcher < InspectionTool
            def run(packages, patch: true)
                initialize_and_load
                packages, = finalize_setup(packages, recursive: false, non_imported_packages: :ignore)
                packages.each do |package_name|
                    pkg = ws.manifest.package_definition_by_name(package_name)
                    if patch
                        pkg.autobuild.importer.patch(pkg.autobuild)
                    else
                        pkg.autobuild.importer.patch(pkg.autobuild, [])
                    end
                end
            end
        end
    end
end
