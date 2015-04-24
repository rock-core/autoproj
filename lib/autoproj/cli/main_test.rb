module Autoproj
    module CLI
        class MainTest < Thor
            desc 'enable [PACKAGES]', 'enable tests for the given packages (or for all packages if none are given)'
            option :deps, default: false,
                desc: 'controls whether the dependencies of the packages given on the command line should be enabled as well (the default is not)'
            def enable(*packages)
                require 'autoproj/cli/test'
                Autoproj.report(silent: true) do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.enable(*args)
                end
            end

            desc 'disable [PACKAGES]', 'disable tests for the given packages (or for all packages if none are given)'
            option :deps, default: false,
                desc: 'controls whether the dependencies of the packages given on the command line should be disabled as well (the default is not)'
            def disable(*packages)
                require 'autoproj/cli/test'
                Autoproj.report(silent: true) do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.disable(*args)
                end
            end

            desc 'list [PACKAGES]', 'show test enable/disable status for the given packages (or all packages if none are given)'
            option :deps, default: false,
                desc: 'controls whether the dependencies of the packages given on the command line should be disabled as well (the default is not)'
            def list(*packages)
                require 'autoproj/cli/test'
                Autoproj.report(silent: true) do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.list(*args)
                end
            end

            desc 'exec [PACKAGES]', 'execute the tests for the given packages, or all if no packages are given on the command line'
            option :deps, default: false,
                desc: 'controls whether to execute the tests of the dependencies of the packages given on the command line (the default is not)'
            def exec(*packages)
                require 'autoproj/cli/test'
                Autoproj.report do
                    cli = Test.new
                    args = cli.validate_options(packages, options)
                    cli.run(*args)
                end
            end
        end
    end
end


