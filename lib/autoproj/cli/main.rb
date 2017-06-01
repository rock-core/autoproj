require 'thor'
require 'tty/color'
require 'autoproj/cli/main_test'
require 'autoproj/cli/main_plugin'

module Autoproj
    module CLI
        def self.basic_setup
            Encoding.default_internal = Encoding::UTF_8
            Encoding.default_external = Encoding::UTF_8
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
            class_option :color, type: :boolean,
                desc: 'enables or disables colored display (enabled by default if the terminal supports it)',
                default: TTY::Color.color?
            class_option :progress, type: :boolean,
                desc: 'enables or disables progress display (enabled by default if the terminal supports it)',
                default: TTY::Color.color?

            no_commands do
                def run_autoproj_cli(filename, classname, report_options, *args, **extra_options)
                    require "autoproj/cli/#{filename}"
                    Autoproj.report(Hash[silent: !options[:debug], debug: options[:debug]].merge(report_options)) do
                        options = self.options.dup
                        # We use --local on the CLI but the APIs are expecting
                        # only_local
                        if options.has_key?('local')
                            options[:only_local] = options.delete('local')
                        end
                        cli = CLI.const_get(classname).new
                        run_args = cli.validate_options(args, options.merge(extra_options))
                        cli.run(*run_args)
                    end
                end
            end

            desc 'bootstrap VCS_TYPE VCS_URL VCS_OPTIONS', 'bootstraps a new autoproj installation. This is usually not called directly, but called from the autoproj_bootstrap standalone script'
            option :reuse,
                banner: 'DIR',
                desc: 'reuse packages already built within the DIR autoproj workspace in this installation, if DIR is not given, reuses the installation whose env.sh is currently sourced'
            option :seed_config,
                banner: 'SEED_CONFIG',
                desc: "a configuration file used to seed the bootstrap's configuration"
            def bootstrap(*args)
                if !File.directory?(File.join(Dir.pwd, '.autoproj'))
                    require 'autoproj/ops/install'
                    ops = Autoproj::Ops::Install.new(Dir.pwd)
                    ops.parse_options(args)
                    ops.run
                    exec Gem.ruby, $0, 'bootstrap', *args
                end
                run_autoproj_cli(:bootstrap, :Bootstrap, Hash[], *args)
            end

            desc 'envsh', 'update the env.sh file'
            def envsh
                run_autoproj_cli(:envsh, :Envsh, Hash[])
            end

            desc 'status [PACKAGES]', 'displays synchronization status between this workspace and the package(s) source'
            option :local, type: :boolean, default: false,
                desc: 'only use locally available information (mainly for distributed version control systems such as git)'
            option :mainline, type: :string,
                desc: "compare to the given baseline. if 'true', the comparison will ignore any override, otherwise it will take into account overrides only up to the given package set"
            option :snapshot, type: :boolean, default: false,
                desc: "use the VCS information as 'versions --no-local' would detect it instead of the one in the configuration"
            option :parallel, aliases: :p, type: :numeric,
                desc: 'maximum number of parallel jobs'
            option :deps, type: :boolean, default: true,
                desc: 'whether only the status of the given packages should be displayed, or of their dependencies as well. -n is a shortcut for --no-deps'
            option :no_deps_shortcut, hide: true, aliases: '-n', type: :boolean,
                desc: 'provide -n for --no-deps'
                default: true
            option :progress, type: :boolean,
                desc: 'show a spinner on long-running packages',
                default: true
            def status(*packages)
                run_autoproj_cli(:status, :Status, Hash[], *packages)
            end

            desc 'doc [PACKAGES]', 'generate API documentation for packages that support it'
            option :deps, type: :boolean, default: true,
                desc: 'control whether documentation should be generated only for the packages given on the command line, or also for their dependencies. -n is a shortcut for --no-deps'
            option :no_deps_shortcut, hide: true, aliases: '-n', type: :boolean,
                desc: 'provide -n for --no-deps'
            def doc(*packages)
                run_autoproj_cli(:doc, :Doc, Hash[], *packages)
            end

            desc 'update [PACKAGES]', 'update packages'
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
                desc: 'controls whether the osdeps subsystem should filter up-to-date packages or not'
            option :deps, default: true, type: :boolean,
                desc: 'whether the package dependencies should be recursively updated (the default) or not. -n is a shortcut for --no-deps'
            option :no_deps_shortcut, hide: true, aliases: '-n', type: :boolean,
                desc: 'provide -n for --no-deps'
            option :reset, default: false, type: :boolean,
                desc: "forcefully resets the repository to the state expected by autoproj's configuration",
                long_desc: "The default is to update the repository if possible, and leave it alone otherwise. With --reset, autoproj update might come back to an older commit than the repository's current state"
            option :force_reset, default: false, type: :boolean,
                desc: "like --reset, but bypasses tests that ensure you won't lose data"
            option :retry_count, default: nil, type: :numeric,
                desc: "force the importer's retry count to this value"
            option :parallel, aliases: :p, type: :numeric,
                desc: 'maximum number of parallel jobs'
            option :mainline, type: :string,
                desc: "compare to the given baseline. if 'true', the comparison will ignore any override, otherwise it will take into account overrides only up to the given package set"
            def update(*packages)
                run_autoproj_cli(:update, :Update, Hash[silent: false], *packages)
            end

            desc 'build [PACKAGES]', 'build packages'
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
                desc: "controls whether the operation should apply to the package's dependencies as well. -n is a shortcut for --no-deps",
                long_desc: <<-EOD
Without --force or --rebuild, the default is true (the build will apply to all packages).
With --force or --rebuild, control whether the force/rebuild action should apply
only on the packages given on the command line, or on their dependencies as well.
In this case, the default is false
                EOD
            option :no_deps_shortcut, hide: true, aliases: '-n', type: :boolean,
                desc: 'provide -n for --no-deps'
            option :parallel, aliases: :p, type: :numeric,
                desc: 'maximum number of parallel jobs'

            def build(*packages)
                run_autoproj_cli(:build, :Build, Hash[silent: false], *packages)
            end

            desc 'cache CACHE_DIR', 'create or update a cache directory that can be given to AUTOBUILD_CACHE_DIR'
            option :keep_going, aliases: :k,
                desc: 'do not stop on errors'
            option :checkout_only, aliases: :c, type: :boolean, default: false,
                desc: "only checkout packages, do not update already-cached ones"
            def cache(*cache_dir)
                run_autoproj_cli(:cache, :Cache, Hash[], *cache_dir)
            end

            desc 'clean [PACKAGES]', 'remove build byproducts for the given packages'
            option :all,
                desc: 'bypass the safety question when you mean to clean all packages'
            def clean(*packages)
                run_autoproj_cli(:clean, :Clean, Hash[], *packages)
            end

            desc 'locate [PACKAGE]', 'return the path to the given package, or the path to the root if no packages are given on the command line'
            option :cache, type: :boolean,
                desc: 'controls whether the resolution should be done by loading the whole configuration (false, slow) or through a cache file (the default)'
            option :prefix, aliases: :p, type: :boolean,
                desc: "outputs the package's prefix directory instead of its source directory"
            option :build, aliases: :b, type: :boolean,
                desc: "outputs the package's build directory instead of its source directory"
            option :log, aliases: :l,
                desc: "outputs the path to a package's log file"
            def locate(*packages)
                run_autoproj_cli(:locate, :Locate, Hash[], *packages)
            end

            desc 'reconfigure', 'pass through all configuration questions'
            option :separate_prefixes, type: :boolean,
                desc: "sets or clears autoproj's separate prefixes mode"
            def reconfigure
                run_autoproj_cli(:reconfigure, :Reconfigure, Hash[])
            end

            desc 'test', 'interface for running tests'
            subcommand 'test', MainTest

            desc 'show [PACKAGES]', 'show informations about package(s)'
            option :mainline, type: :string,
                desc: "compare to the given baseline. if 'true', the comparison will ignore any override, otherwise it will take into account overrides only up to the given package set"
            option :env, type: :boolean,
                desc: "display the package's own environment", default: false
            option :short, desc: 'display a package summary with one package line'
            option :recursive, desc: 'display the package and their dependencies (the default is to only display selected packages)',
                type: :boolean, default: false
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
            option :config, type: :boolean,
                default: nil,
                banner: '',
                desc: "controls whether the package sets should be versioned as well",
                long_desc: <<-EOD
This is the default if no packages are given on the command line, or if the
autoproj main configuration directory is. Note that if --config but no packages
are given, the packages will not be versioned. In other words,
   autoproj versions # versions everything, configuration and packages
   autoproj versions --config # versions only the configuration
   autoproj versions autoproj/ # versions only the configuration
   autoproj versions autoproj a/package # versions the configuration and the specified package(s)
                EOD
            option :keep_going, aliases: :k, type: :boolean,
                default: false,
                banner: '',
                desc: 'do not stop if some package cannot be versioned'
            option :replace, type: :boolean,
                default: false,
                desc: 'in combination with --save, controls whether an existing file should be updated or replaced'
            option :deps, type: :boolean, default: false,
                desc: 'whether both packages and their dependencies should be versioned, or only the selected packages (the latter is the default)'
            option :local, type: :boolean, default: false,
                desc: 'whether we should access the remote server to verify that the snapshotted state is present'
            option :save, type: :string,
                desc: 'save to the given file instead of displaying it on the standard output'
            def versions(*packages)
                run_autoproj_cli(:versions, :Versions, Hash[], *packages, deps: true)
            end

            stop_on_unknown_option! :log
            desc 'log', "shows the log of autoproj updates"
            def log(*args)
                run_autoproj_cli(:log, :Log, Hash[], *args)
            end

            desc 'reset VERSION_ID', 'resets packages to the state stored in the required version'
            long_desc <<-EOD
reset VERSION_ID will infer the state of packages from the state stored in the requested version,
and reset the packages to these versions. VERSION_ID can be:
 - an autoproj log entry (e.g. autoproj@{10})
 - a branch or tag from the autoproj main build configuration
EOD
            option :freeze, type: :boolean, default: false,
                desc: 'whether the version we reset to should be saved in overrides.d or not'
            def reset(version_id)
                run_autoproj_cli(:reset, :Reset, Hash[], version_id)
            end

            desc 'tag [TAG_NAME] [PACKAGES]', 'save the package current versions as a tag, or lists the available tags if given no arguments.'
            long_desc <<-EOD
The tag subcommand stores the state of all packages (or of the packages selected
on the command line) into a tag in the build configuration. This state can be
retrieved later on by using "autoproj reset"

If given no arguments, will list the existing tags
EOD
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

            desc 'commit [PACKAGES]', 'save the package current versions as a new commit in the main build configuration'
            long_desc <<-EOD
The commit subcommand stores the state of all packages (or of the packages
selected on the command line) into a new commit in the currently checked-out
branch of the build configuration. This state can be retrieved later on by using
"autoproj reset"

If given no arguments, will list the existing tags
EOD
            option :package_sets, type: :boolean,
                desc: 'commit the package set state as well (enabled by default)'
            option :keep_going, aliases: :k, type: :boolean,
                banner: '',
                desc: 'do not stop on build or checkout errors'
            option :message, aliases: :m, type: :string,
                desc: 'the message to use for the new commit (the default is to mention the creation of the tag)'
            def commit(*packages)
                run_autoproj_cli(:commit, :Commit, Hash[], *packages, deps: true)
            end

            desc 'switch-config VCS URL [OPTIONS]', 'switches the main build configuration'
            def switch_config(*args)
                run_autoproj_cli(:switch_config, :SwitchConfig, Hash[], *args)
            end

            desc 'query [QUERY]', 'searches for packages matching a query string. With no query string, matches all packages.'
            long_desc <<-EOD
Finds packages that match query_string and displays information about them (one per line)
By default, only the package name is displayed. It can be customized with the --format option

QUERY KEYS

  autobuild.name: the package name,
  autobuild.srcdir: the package source directory,
  autobuild.class.name: the package class,
  vcs.type: the VCS type (as used in the source.yml files),
  vcs.url: the URL from the VCS,
  package_set.name: the name of the package set that defines the package

FORMAT SPECIFICATION

The format is a string in which special values can be expanded using a $VARNAME format. The following variables are accepted:

  NAME: the package name,

  SRCDIR: the full path to the package source directory,

  PREFIX: the full path to the package installation directory
            EOD
            option :search_all, type: :boolean,
                desc: 'search in all defined packages instead of only in those selected selected in the layout'
            option :format, type: :string,
                desc: "customize what should be displayed. See FORMAT SPECIFICATION above"
            def query(query_string = nil)
                run_autoproj_cli(:query, :Query, Hash[], *Array(query_string))
            end

            desc 'install_stage2 ROOT_DIR [ENVVAR=VALUE ...]', 'used by autoproj_install to finalize the installation',
                hide: true
            def install_stage2(root_dir, *vars)
                require 'autoproj/ops/install'
                ops = Autoproj::Ops::Install.new(root_dir)
                if options[:color] then ops.autoproj_options << "--color"
                else ops.autoproj_options << "--no-color"
                end
                if options[:progress] then ops.autoproj_options << "--progress"
                else ops.autoproj_options << "--no-progress"
                end
                ops.stage2(*vars)
            end

            desc 'plugin', 'interface to manage autoproj plugins'
            subcommand 'plugin', MainPlugin

            desc 'patch', 'applies patches necessary for the selected package',
                hide: true
            def patch(*packages)
                run_autoproj_cli(:patcher, :Patcher, Hash[], *packages, patch: true)
            end

            desc 'unpatch', 'remove any patch applied on the selected package',
                hide: true
            def unpatch(*packages)
                run_autoproj_cli(:patcher, :Patcher, Hash[], *packages, patch: false)
            end

            desc 'manifest', 'select or displays the active manifest'
            def manifest(*name)
                run_autoproj_cli(:manifest, :Manifest, Hash[silent: true], *name)
            end
        end
    end
end

