require "autoproj/cli/inspection_tool"

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

            def enable(user_selection, **options)
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

            def disable(user_selection, **options)
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

            def list(user_selection, **options)
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
                puts format(out_format, "Package Name", "Enabled", "Available")
                lines.each do |name, enabled, available|
                    puts(format(out_format, name, (!!enabled).to_s, (!!available).to_s)) # rubocop:disable Style/DoubleNegation
                end
            end

            def run(user_selection, **options)
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
                return if package_names.empty?

                packages = package_names.map do |pkg_name|
                    ws.manifest.find_package_definition(pkg_name)
                end

                apply_to_packages(packages, parallel: options[:parallel])
            end

            def apply_to_packages(packages, parallel: ws.config.parallel_build_level)
                if @report_path
                    reporting = Ops::PhaseReporting.new(
                        @utility_name, @report_path,
                        method(:package_metadata)
                    )
                end

                reporting&.initialize_incremental_report
                Autobuild.apply(
                    packages.map(&:name), "autoproj-#{@utility_name}",
                    [@utility_name], parallel: parallel
                ) do |pkg, phase|
                    reporting&.report_incremental(pkg) if phase == utility_name
                end
            ensure
                reporting&.create_report(packages.map(&:autobuild))
            end

            def package_metadata(autobuild_package)
                # rubocop:disable Style/DoubleNegation
                u = autobuild_package.utility(@utility_name)
                {
                    "source_dir" => u.source_dir,
                    "target_dir" => u.target_dir,
                    "available" => !!u.available?,
                    "enabled" => !!u.enabled?,
                    "invoked" => !!u.invoked?,
                    "success" => !!u.success?,
                    "installed" => !!u.installed?
                }
                # rubocop:enable Style/DoubleNegation
            end
        end
    end
end
