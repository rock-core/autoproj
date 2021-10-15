require "autoproj/cli/update"
require "autoproj/ops/build"

module Autoproj
    module CLI
        class Build < Update
            def validate_options(selected_packages, options)
                selected_packages, options =
                    super(selected_packages, options.merge(
                        checkout_only: true, aup: options[:amake]
                    ))

                options[:deps] = false if options[:no_deps_shortcut]
                if options[:deps].nil?
                    options[:deps] =
                        !(options[:rebuild] || options[:force])
                end
                [selected_packages, options]
            end

            def run(selected_packages, **options)
                build_options, options = filter_options(
                    options,
                    force: false,
                    rebuild: false,
                    parallel: nil,
                    confirm: true,
                    not: Array.new
                )

                command_line_selection, source_packages, _osdep_packages =
                    super(selected_packages,
                          ignore_errors: options[:keep_going],
                          checkout_only: true,
                          report: false,
                          **options)

                parallel = build_options[:parallel] || ws.config.parallel_build_level

                return if source_packages.empty?

                active_packages = source_packages - build_options[:not]

                # Disable all packages that are not selected
                ws.manifest.each_autobuild_package do |pkg|
                    next if active_packages.include?(pkg.name)

                    pkg.disable
                end

                Autobuild.ignore_errors = options[:keep_going]

                ops = Ops::Build.new(ws.manifest, report_path: ws.build_report_path)
                if build_options[:rebuild] || build_options[:force]
                    packages_to_rebuild =
                        if options[:deps] || command_line_selection.empty?
                            source_packages
                        else
                            command_line_selection
                        end

                    if command_line_selection.empty?
                        # If we don't have an explicit package selection, we want to
                        # make sure that the user really wants this
                        mode_name = if build_options[:rebuild] then "rebuild"
                                    else
                                        "force-build"
                                    end
                        if build_options[:confirm] != false
                            opt = BuildOption.new(
                                "", "boolean",
                                {
                                    doc: "this is going to trigger a #{mode_name} "\
                                        "of all packages. Is that really what you want ?"
                                }, nil
                            )
                            raise Interrupt unless opt.ask(false)
                        end

                        if build_options[:rebuild]
                            ops.rebuild_all
                        else
                            ops.force_build_all
                        end
                    elsif build_options[:rebuild]
                        ops.rebuild_packages(packages_to_rebuild, source_packages)
                    else
                        ops.force_build_packages(packages_to_rebuild, source_packages)
                    end
                    return
                end

                Autobuild.do_build = true
                ops.build_packages(source_packages, parallel: parallel)
                Main.run_post_command_hook(:build, ws, source_packages: source_packages)
            ensure
                # Update env.sh, but only if we managed to load the configuration
                export_env_sh if source_packages
            end
        end
    end
end
