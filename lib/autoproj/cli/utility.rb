require 'autoproj/cli/inspection_tool'

module Autoproj
    module CLI
        class Utility < InspectionTool
            def initialize(ws, name: nil, report_path: nil)
                @utility_name = name
                @report_path = report_path
                super(ws)
            end

            attr_reader :utility_name
            def default(enabled)
                ws.load_config
                ws.config.utility_default(utility_name, enabled)
                ws.config.save
            end

            def enable(user_selection, options = {})
                if user_selection.empty?
                    ws.load_config
                    ws.config.utility_enable_all(utility_name)
                else
                    initialize_and_load
                    selection, = finalize_setup(
                        user_selection,
                        recursive: options[:deps],
                        non_imported_packages: :return
                    )
                    ws.config.utility_enable(utility_name, *selection)
                end
                ws.config.save
            end

            def disable(user_selection, options = {})
                if user_selection.empty?
                    ws.load_config
                    ws.config.utility_disable_all(utility_name)
                else
                    initialize_and_load
                    selection, = finalize_setup(
                        user_selection,
                        recursive: options[:deps],
                        non_imported_packages: :return
                    )
                    ws.config.utility_disable(utility_name, *selection)
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
                    lines << [
                        pkg.name,
                        pkg.send("#{utility_name}_utility").enabled?,
                        pkg.send("#{utility_name}_utility").available?
                    ]
                end
                lines = lines.sort_by { |name, _| name }
                w     = lines.map { |name, _| name.length }.max
                out_format = "%-#{w}s %-7s %-9s"
                puts format(out_format, 'Package Name', 'Enabled', 'Available')
                lines.each do |name, enabled, available|
                    puts(format(out_format, name, (!!enabled).to_s, (!!available).to_s))
                end
            end

            def run(user_selection, options = {})
                options[:parallel] ||= ws.config.parallel_build_level
                initialize_and_load

                user_selection, = normalize_command_line_package_selection(user_selection)
                package_names, _, resolved_selection = finalize_setup(
                    user_selection,
                    recursive: user_selection.empty? || options[:deps]
                )

                validate_user_selection(user_selection, resolved_selection)
                if package_names.empty?
                    raise CLIInvalidArguments, "autoproj: the provided package "\
                        "is not selected for build"
                end

                packages = package_names.map do |pkg_name|
                    ws.manifest.find_package_definition(pkg_name)
                end

                Autobuild.apply(
                    package_names,
                    "autoproj-#{utility_name}",
                    [utility_name],
                    parallel: options[:parallel]
                )

            ensure
                create_report(packages) if packages && @report_path
            end

            def package_metadata(package)
                u = package.autobuild.utility(@utility_name)
                {
                    'source_dir' => u.source_dir,
                    'target_dir' => u.target_dir,
                    'available' => !!u.available?,
                    'enabled' => !!u.enabled?,
                    'invoked' => !!u.invoked?,
                    'success' => !!u.success?,
                    'installed' => !!u.installed?,
                }
            end

            def create_report(packages)
                info = packages.each_with_object({}) do |p, map|
                    map[p.name] = package_metadata(p)
                end

                FileUtils.mkdir_p File.dirname(@report_path)
                File.open(@report_path, 'w') do |io|
                    dump = JSON.dump(
                        "#{@utility_name}_report" => {
                            'timestamp' => Time.now,
                            'packages' => info
                        }
                    )
                    io.write dump
                end
            end
        end
    end
end
