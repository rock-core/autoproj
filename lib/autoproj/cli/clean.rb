require 'autoproj/cli/inspection_tool'
require 'tty/prompt'

module Autoproj
    module CLI
        class Clean < InspectionTool
            def validate_options(packages, options)
                packages, options = super
                if packages.empty? && !options[:all]
                    prompt = TTY::Prompt.new
                    if !prompt.yes?("this is going to clean all packages. Is that really what you want ?")
                        raise Interrupt
                    end
                end
                return packages, options
            end

            def run(selection, options = Hash.new)
                initialize_and_load
                packages, _ = normalize_command_line_package_selection(selection)

                deps = if options.has_key?(:deps)
                           options[:deps]
                       else
                           selection.empty?
                       end

                source_packages, * = resolve_selection(
                    packages,
                    recursive: deps)
                if source_packages.empty?
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

