require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Clean < InspectionTool
            def parse_options(argv)
                options = Hash.new

                bypass_clean_all_check = false
                parser = OptionParser.new do |opt|
                    opt.banner = "autoproj clean [PACKAGES]"
                    opt.on '--all', 'bypass the interactive question when you mean to clean all packages' do
                        bypass_clean_all_check = true
                    end
                end

                selection = parser.parse(argv)

                if selection.empty? && !bypass_clean_all_check
                    opt = BuildOption.new("", "boolean", {:doc => "this is going to clean all packages. Is that really what you want ?"}, nil)
                    if !opt.ask(false)
                        raise Interrupt
                    end
                end

                return parser.parse(argv), options
            end

            def run(selection, options = Hash.new)
                packages, resolved_selection = resolve_selection(
                    ws.manifest,
                    selection,
                    recursive: false,
                    ignore_non_imported_packages: true)
                if packages.empty?
                    raise ArgumentError, "no packages or OS packages match #{selection.join(" ")}"
                end

                packages.each do |pkg_name|
                    ws.manifest.find_autobuild_package(pkg_name).
                        prepare_for_rebuild
                end
            end
        end
    end
end

