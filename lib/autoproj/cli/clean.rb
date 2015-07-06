require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Clean < InspectionTool
            def validate_options(packages, options)
                packages, options = super
                if packages.empty? && !options[:all]
                    opt = BuildOption.new("", "boolean", {:doc => "this is going to clean all packages. Is that really what you want ?"}, nil)
                    if !opt.ask(false)
                        raise Interrupt
                    end
                end
                return packages, options
            end

            def run(selection, options = Hash.new)
                initialize_and_load
                packages, _ = normalize_command_line_package_selection(selection)
                source_packages, * = resolve_selection(
                    ws.manifest,
                    selection,
                    recursive: false,
                    ignore_non_imported_packages: true)
                if packages.empty?
                    raise ArgumentError, "no packages or OS packages match #{selection.join(" ")}"
                end

                source_packages.each do |pkg_name|
                    ws.manifest.find_autobuild_package(pkg_name).
                        prepare_for_rebuild
                end
            end
        end
    end
end

