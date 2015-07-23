require 'thor'
require 'autoproj'
require 'autoproj/cli/main_test'

module Autoproj
    module CLI
        def self.basic_setup
            Encoding.default_internal = Encoding::UTF_8
            Encoding.default_external = Encoding::UTF_8

            Autobuild::Reporting << Autoproj::Reporter.new
            Autobuild::Package.clear
        end

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
            option :mainline, type: :string,
                desc: "compare to the given baseline. if 'true', the comparison will ignore any override, otherwise it will take into account overrides only up to the given package set"
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
                default: true,
                desc: "enable or disable osdeps handling"
            option :from, type: :string,
                desc: 'use this existing autoproj installation to check out the packages (for importers that support this)'
            option :checkout_only, aliases: :c, type: :boolean, default: false,
                desc: "only checkout packages, do not update existing ones"
            option :local, type: :boolean, default: false,
                desc: "use only local information for the update (for importers that support it)"
            option :osdeps_filter_uptodate, default: true, type: :boolean,
                desc: 'controls whether the osdeps subsystem should filter up-to-date packages or not', default: true
            option :deps, default: true, type: :boolean,
                desc: 'whether the package dependencies should be recursively updated (the default) or not'
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
                run_autoproj_cli(:build, :Build, Hash[silent: false], *packages)
            end

            desc 'cache CACHE_DIR', 'create or update a cache directory that can be given to AUTOBUILD_CACHE_DIR'
            option :keep_going, aliases: :k,
                desc: 'do not stop on errors'
            option :checkout_only, aliases: :c, type: :boolean, default: false,
                desc: "only checkout packages, do not update already-cached ones"
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
            option :build, aliases: :b, type: :boolean,
                desc: "outputs the package's build directory instead of its source directory"
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

            desc 'show', 'show informations about package(s)'
            option :mainline, type: :string,
                desc: "compare to the given baseline. if 'true', the comparison will ignore any override, otherwise it will take into account overrides only up to the given package set"
            def show(*packages)
                run_autoproj_cli(:show, :Show, Hash[], *packages)
            end

            desc 'osdeps [PACKAGES]', 'install/update OS dependencies that are required by the given package (or for the whole installation if no packages are given'
            option :update, type: :boolean, default: true,
                desc: 'whether already installed packages should be updated or not'
            def osdeps(*packages)
                run_autoproj_cli(:osdeps, :OSDeps, Hash[], *packages)
            end

            desc 'versions [PACKAGES]', 'generate a version file for the given packages, or all packages if none are given'
            option :package_sets, type: :boolean,
                default: nil,
                banner: '',
                desc: 'controls whether the package sets should be versioned as well. This is the default if no packages are given on the command line or if the autoproj directory is'
            option :keep_going, aliases: :k, type: :boolean,
                default: false,
                banner: '',
                desc: 'do not stop if some package cannot be versioned'
            option :replace, type: :boolean,
                default: false,
                desc: 'in combination with --save, controls whether an existing file should be updated or replaced'
            option :save, type: :string,
                desc: 'save to the given file instead of displaying it on the standard output'
            def versions(*packages)
                run_autoproj_cli(:versions, :Versions, Hash[], *packages)
            end

            stop_on_unknown_option! :log
            desc 'log', "shows the log of autoproj updates"
            def log(*args)
                run_autoproj_cli(:log, :Log, Hash[], *args)
            end

            desc 'reset VERSION_ID', 'resets packages to the required version (either reflog from autoproj log or commit/tag in the build configuration'
            option :freeze, type: :boolean, default: false,
                desc: 'whether the version we reset to should be saved in overrides.d or not'
            def reset(version_id)
                run_autoproj_cli(:reset, :Reset, Hash[], version_id)
            end

            desc 'tag [TAG_NAME] [PACKAGES]', 'save the package current versions as a tag in the main build configuration, or lists the available tags if given no arguments'
            option :package_sets, type: :boolean,
                desc: 'commit the package set state as well (enabled by default)'
            option :keep_going, aliases: :k, type: :boolean,
                banner: '',
                desc: 'do not stop on build or checkout errors'
            option :message, aliases: :m, type: :string,
                desc: 'the message to use for the new commit (the default is to mention the creation of the tag)'
            def tag(tag_name = nil, *packages)
                run_autoproj_cli(:tag, :Tag, Hash[], tag_name, *packages)
            end

            desc 'tag [PACKAGES]', 'save the package current versions as a new commit in the main build configuration'
            option :package_sets, type: :boolean,
                desc: 'commit the package set state as well (enabled by default)'
            option :keep_going, aliases: :k, type: :boolean,
                banner: '',
                desc: 'do not stop on build or checkout errors'
            option :message, aliases: :m, type: :string,
                desc: 'the message to use for the new commit (the default is to mention the creation of the tag)'
            def tag(*packages)
                run_autoproj_cli(:tag, :Tag, Hash[], *packages)
            end

            desc 'switch-config VCS URL [OPTIONS]', 'switches the main build configuration'
            def switch_config(*args)
                run_autoproj_cli(:switch_config, :SwitchConfig, Hash[], *args)
            end

            desc 'query <query string>', 'searches for packages matching a query string'
            long_desc <<-EOD
  Finds packages that match query_string and displays information about them (one per line)
  By default, only the package name is displayed. It can be customized with the --format option

  QUERY KEYS
    autobuild.name: the package name
    autobuild.srcdir: the package source directory
    autobuild.class.name: the package class
    vcs.type: the VCS type (as used in the source.yml files)
    vcs.url: the URL from the VCS. The exact semantic of it depends on the VCS type
    package_set.name: the name of the package set that defines the package

  FORMAT SPECIFICATION

  The format is a string in which special values can be expanded using a $VARNAME format. The following variables are accepted:
    NAME: the package name
    SRCDIR: the full path to the package source directory
    PREFIX: the full path to the package installation directory
            EOD
            option :search_all, type: :boolean,
                desc: 'search in all defined packages instead of only in those selected selected in the layout'
            option :format, type: :string,
                desc: "customize what should be displayed. See FORMAT SPECIFICATION above"
            def query(query_string)
                run_autoproj_cli(:query, :Query, Hash[], query_string)
            end
        end
    end
end

