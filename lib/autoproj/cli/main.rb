require 'thor'
require 'autoproj/cli/main_test'

module Autoproj
    module CLI
        class Main < Thor
            class_option :verbose, type: :boolean,
                desc: 'turns verbose output',
                default: false
            class_option :debug, type: :boolean,
                desc: 'turns debugging output',
                default: false
            class_option :silent, type: :boolean,
                desc: 'tell autoproj to not display anything',
                default: false
            class_option :progress, type: :boolean,
                desc: 'enables or disables progress display (enabled by default)',
                default: true

            no_commands do
                def run_autoproj_cli(filename, classname, report_options, *args)
                    require "autoproj/cli/#{filename}"
                    Autoproj.report(Hash[silent: true].merge(report_options)) do
                        cli = CLI.const_get(classname).new
                        run_args = cli.validate_options(args, self.options)
                        cli.run(*run_args)
                    end
                end
            end

            desc 'bootstrap VCS_TYPE VCS_URL VCS_OPTIONS', 'bootstraps a new autoproj installation. This is usually not called directly, but called from the autoproj_bootstrap standalone script'
            option :reuse,
                banner: 'DIR',
                desc: 'reuse packages already built within the DIR autoproj workspace in this installation, if DIR is not given, reuses the installation whose env.sh is currently sourced'
            def bootstrap(*args)
                run_autoproj_cli(:bootstrap, :Bootstrap, Hash[], *args)
            end

            desc 'envsh', 'update the env.sh file'
            def envsh
                run_autoproj_cli(:envsh, :Envsh, Hash[])
            end

            desc 'status [PACKAGES]', 'displays synchronization status between this workspace and the package(s) source'
            option :only_local,
                desc: 'only use locally available information (mainly for distributed version control systems such as git)'
            def status(*packages)
                run_autoproj_cli(:status, :Status, Hash[], *packages)
            end

            desc 'doc', 'generate API documentation for packages that support it'
            option :without_deps, desc: 'generate documentation for the packages given on the command line, and not for their dependencies'
            def doc(*packages)
                run_autoproj_cli(:doc, :Doc, Hash[], *packages)
            end

            desc 'update', 'update packages'
            option :aup, default: false, hide: true, type: :boolean,
                desc: 'behave like aup'
            option :all, default: false, hide: true, type: :boolean,
                desc: 'when in aup mode, update all packages instead of only the local one'
            option :keep_going, aliases: :k, type: :boolean,
                banner: '',
                desc: 'do not stop on build or checkout errors'
            option :config, type: :boolean,
                desc: "(do not) update configuration. The default is to update configuration if explicitely selected or if no additional arguments are given on the command line, and to not do it if packages are explicitely selected on the command line"
            option :autoproj, type: :boolean,
                desc: "(do not) update autoproj. This is automatically enabled only if no arguments are given on the command line"
            option :osdeps, type: :boolean,
                desc: "enable or disable osdeps handling"
            option :from, type: :string,
                desc: 'use this existing autoproj installation to check out the packages (for importers that support this)'
            option :checkout_only, aliases: :c, type: :boolean, default: false,
                desc: "only checkout packages, do not update existing ones"
            option :local, type: :boolean, default: false,
                desc: "use only local information for the update (for importers that support it)"
            option :osdeps_filter_uptodate, default: true, type: :boolean,
                desc: 'controls whether the osdeps subsystem should filter up-to-date packages or not', default: true
            def update(*packages)
                run_autoproj_cli(:update, :Update, Hash[silent: false], *packages)
            end

            desc 'build', 'build packages'
            option :amake, default: false, hide: true, type: :boolean,
                desc: 'behave like amake'
            option :all, default: false, hide: true, type: :boolean,
                desc: 'when in amake mode, build all packages instead of only the local one'
            option :keep_going, aliases: :k, type: :boolean, default: false,
                desc: 'do not stop on build or checkout errors'
            option :force, type: :boolean, default: false,
                desc: 'force reconfiguration-build cycle on the requested packages, even if they do not seem to need it'
            option :rebuild, type: :boolean, default: false,
                desc: 'clean and build the requested packages'
            option :osdeps, type: :boolean,
                desc: 'controls whether missing osdeps should be installed. In rebuild mode, also controls whether the osdeps should be reinstalled or not (the default is to reinstall them)' 
            option :deps, type: :boolean,
                desc: 'in force or rebuild modes, control whether the force/rebuild action should apply only on the packages given on the command line, or on their dependencies as well (the default is --no-deps)'
            def build(*packages)
                run_autoproj_cli(:build, :Build, Hash[], *packages)
            end

            desc 'cache CACHE_DIR', 'create or update a cache directory that can be given to AUTOBUILD_CACHE_DIR'
            option :keep_going, alias: :k,
                desc: 'do not stop on errors'
            def cache(cache_dir)
                run_autoproj_cli(:cache, :Cache, Hash[], cache_dir)
            end

            desc 'clean [PACKAGES]', 'remove build byproducts for the given packages'
            option :all,
                desc: 'bypass the safety question when you mean to clean all packages'
            def clean(*packages)
                run_autoproj_cli(:clean, :Clean, Hash[], *packages)
            end

            desc 'locate [PACKAGE]', 'return the path to the given package, or the path to the root if no packages are given on the command line'
            def locate(package = nil)
                run_autoproj_cli(:locate, :Locate, Hash[], *Array(package))
            end

            desc 'reconfigure', 'pass through all configuration questions'
            option :separate_prefixes, type: :boolean,
                desc: "sets or clears autoproj's separate prefixes mode"
            def reconfigure
                run_autoproj_cli(:reconfigure, :Reconfigure, Hash[])
            end

            desc 'test', 'interface for running tests'
            subcommand 'test', MainTest
        end
    end
end

