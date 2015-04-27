require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class OSDeps < InspectionTool
            def validate_options(package_names, options = Hash.new)
                package_names, options = super

                if package_names.empty?
                    package_names = ws.manifest.default_packages(false)
                end

                return package_names, options
            end

            def run(user_selection, options = Hash.new)
                packages, resolved_selection, _ =
                    finalize_setup(user_selection,
                                   recursive: false,
                                   ignore_non_imported_packages: true)

                osdeps = Set.new
                packages.each do |name|
                    result = ws.manifest.resolve_package_name(name, filter: false)
                    packages, pkg_osdeps = result.partition { |pkg_type, _| pkg_type == :package }
                    packages = packages.map(&:last)
                    osdeps   |= pkg_osdeps.map(&:last).to_set

                    packages.each do |pkg_name|
                        osdeps |= ws.manifest.find_autobuild_package(pkg_name).os_packages.to_set
                    end

                end

                ws.osdeps.install(
                    osdeps,
                    install_only: !options[:update])
            end
        end
    end
end

