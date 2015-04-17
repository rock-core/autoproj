require 'autoproj/cli/update'

module Autoproj
    module CLI
        class Build < Update
            def validate_options(selected_packages, options)
                selected_packages, options = super
                if options[:amake] && selected_packages.empty? && !options[:all]
                    selected_packages = ['.']
                end

                if !options.has_key?(:deps)
                    options[:deps] = 
                        !(options[:rebuild] || options[:forced_build])
                end
                return selected_packages, options
            end

            def run(selected_packages, options)
                build_options, options = filter_options options,
                    forced_build: false,
                    rebuild: false

                Autobuild.ignore_errors = options[:keep_going]

                command_line_selection, all_enabled_packages =
                    super(selected_packages, options.merge(checkout_only: true))

                ops = Ops::Build.new(ws.manifest)
                if build_options[:rebuild] || build_options[:forced_build]
                    packages_to_rebuild =
                        if options[:deps] || command_line_selection.empty?
                            all_enabled_packages
                        else command_line_selection
                        end

                    if command_line_selection.empty?
                        # If we don't have an explicit package selection, we want to
                        # make sure that the user really wants this
                        mode_name = if options[:rebuild] then 'rebuild'
                                    else 'force-build'
                                    end
                        opt = BuildOption.new("", "boolean", {:doc => "this is going to trigger a #{mode_name} of all packages. Is that really what you want ?"}, nil)
                        if !opt.ask(false)
                            raise Interrupt
                        end
                        if build_options[:rebuild]
                            if options[:osdeps]
                                ws.osdeps.reinstall
                            end
                            ops.rebuild_all
                        else
                            ops.force_build_all
                        end
                    elsif build_options[:rebuild]
                        ops.rebuild_packages(packages_to_rebuild, all_enabled_packages)
                    else
                        ops.force_build_packages(packages_to_rebuild, all_enabled_packages)
                    end
                    return
                end

                Autobuild.do_build = true
                ops.build_packages(all_enabled_packages)
                Autobuild.apply(all_enabled_packages, "autoproj-build", ['install'])
            end
        end
    end
end


