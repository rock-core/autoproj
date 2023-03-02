module Autoproj
    module CLI
        class MainDoc < Thor
            namespace "doc"

            default_command "exec"

            no_commands do
                def report(report_options = Hash.new)
                    options = self.options.merge(parent_options)
                    extra_options = Hash.new
                    if options[:tool]
                        Autobuild::Subprocess.transparent_mode = true
                        Autobuild.silent = true
                        Autobuild.color = false
                        report_options[:silent] = true
                        report_options[:on_package_failures] = :exit_silent
                        extra_options[:silent] = true
                    end
                    Autoproj.report(**Hash[debug: options[:debug]].merge(report_options)) do
                        yield(extra_options)
                    end
                end
            end

            desc "enable [PACKAGES]", "enable docs for the given packages (or for all packages if none are given)"
            option :deps, type: :boolean, default: false,
                          desc: "controls whether the dependencies of the packages given on the command line should be enabled as well (the default is not)"
            def enable(*packages)
                require "autoproj/cli/doc"
                options = self.options.merge(parent_options)
                report(silent: true) do
                    cli = Doc.new
                    *args, options = cli.validate_options(packages, options)
                    cli.enable(*args, **options)
                end
            end

            desc "disable [PACKAGES]", "disable docs for the given packages (or for all packages if none are given)"
            option :deps, type: :boolean, default: false,
                          desc: "controls whether the dependencies of the packages given on the command line should be disabled as well (the default is not)"
            def disable(*packages)
                require "autoproj/cli/doc"
                options = self.options.merge(parent_options)
                report(silent: true) do
                    cli = Doc.new
                    *args, options = cli.validate_options(packages, options)
                    cli.disable(*args, **options)
                end
            end

            desc "list [PACKAGES]", "show doc enable/disable status for the given packages (or all packages if none are given)"
            option :deps, type: :boolean, default: true,
                          desc: "controls whether the dependencies of the packages given on the command line should be disabled as well (the default is not)"
            def list(*packages)
                require "autoproj/cli/doc"
                options = self.options.merge(parent_options)
                report(silent: true) do
                    cli = Doc.new
                    *args, options = cli.validate_options(packages, options)
                    cli.list(*args, **options)
                end
            end

            desc "exec [PACKAGES]", "generate documentation for the given packages, or all if no packages are given on the command line"
            option :deps, type: :boolean, default: false,
                          desc: "controls whether to generate documentation of the dependencies of the packages given on the command line (the default is not)"
            option :no_deps_shortcut, hide: true, aliases: "-n", type: :boolean,
                                      desc: "provide -n for --no-deps"
            option :parallel, aliases: :p, type: :numeric,
                              desc: "maximum number of parallel jobs"
            option :tool, type: :boolean, default: false,
                          desc: "run in tool mode, which do not redirect the subcommand's outputs"
            option :color, type: :boolean, default: TTY::Color.color?,
                           desc: "enables or disables colored display (enabled by default if the terminal supports it)"
            option :progress, type: :boolean, default: TTY::Color.color?,
                              desc: "enables or disables progress display (enabled by default if the terminal supports it)"
            def exec(*packages)
                require "autoproj/cli/doc"
                options = self.options.merge(parent_options)
                report do |extra_options|
                    cli = Doc.new
                    options.delete(:tool)
                    *args, options = cli.validate_options(packages, options.merge(extra_options))
                    cli.run(*args, **options)
                end
            end
        end
    end
end
