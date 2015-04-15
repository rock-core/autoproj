require 'autoproj/cli/update'

module Autoproj
    module CLI
        class Build < Update
            def parse_amake_options(args)
                parse_options(args, true)
            end

            def parse_options(args, amake = false)
                options = Hash[
                    keep_going: false,
                    osdeps: true,
                    nice: nil]

                build_all = false
                parser = OptionParser.new do |opt|
                    if amake
                        opt.banner = ["amake", "builds packages within the autoproj workspace"].join("\n")
                        opt.on '--all', 'build the whole workspace instead of only the current package and its dependencies' do
                            build_all = true
                        end
                    else
                        opt.banner = ["autoproj builds", "builds packages within the autoproj workspace"].join("\n")
                    end

                    
                    opt.on '-k', '--keep-going' do
                        options[:keep_going] = true
                    end
                    opt.on '--force' do
                        options[:forced_build] = true
                        options[:rebuild] = false
                    end
                    opt.on '--rebuild' do
                        options[:forced_build] = false
                        options[:rebuild] = true
                    end
                    opt.on '--[no-]osdeps', 'controls whether missing osdeps should be installed. In rebuild mode, also controls whether the osdeps should be reinstalled or not (the default is to reinstall them)' do |flag|
                        options[:osdeps] = flag
                    end
                    opt.on '--[no-]deps' do |flag|
                        options[:with_deps] = flag
                    end
                end
                common_options(parser)

                if !options.has_key?(:with_deps)
                    options[:with_deps] = 
                        !(options[:rebuild] || options[:forced_build])
                end
                selected_packages = parser.parse(args)
                if amake && !build_all && selected_packages.empty?
                    selected_packages << '.'
                end

                ws.osdeps.silent = Autoproj.silent?
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
                        if options[:with_deps] || command_line_selection.empty?
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


