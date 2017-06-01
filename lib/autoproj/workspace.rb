require 'autoproj/ops/import'
require 'autoproj/ops/install'

module Autoproj
    class Workspace < Ops::Loader
        attr_reader :root_dir

        attr_accessor :config
        attr_reader :env

        # The installation manifest
        #
        # @return [Manifest]
        attr_reader :manifest

        attr_reader :loader

        attr_reader :os_package_resolver
        attr_reader :os_package_installer

        # The keyword used to represent the current ruby version.
        #
        # It is e.g. ruby21 for ruby 2.1.
        #
        # It is initialized to the local ruby version in {#initialize}. If one
        # intends to override it, one must do it before {#setup} gets called
        #
        # This is aliased to 'ruby' in the osdep system, so one that depends on
        # ruby should only refer to 'ruby' unless a specific version is
        # requested.
        #
        # It is also used as an osdep suffix when loading osdep files (i.e. the
        # osdep system will attempt to load `.osdep-ruby21` files on ruby 2.1 in
        # addition to the plain .osdep files.
        #
        # @return [String]
        attr_accessor :ruby_version_keyword

        # Suffixes that should be considered when loading osdep files
        #
        # {#ruby_version_keyword} is automatically added there in {#setup}
        attr_reader :osdep_suffixes

        def initialize(root_dir,
                       os_package_resolver: OSPackageResolver.new,
                       package_managers: OSPackageInstaller::PACKAGE_MANAGERS)
            @root_dir = root_dir
            @ruby_version_keyword = "ruby#{RUBY_VERSION.split('.')[0, 2].join("")}"
            @osdep_suffixes = Array.new

            @loader = loader
            @env = Environment.new
            env.prepare(root_dir)
            env.source_before(File.join(dot_autoproj_dir, 'env.sh'))

            @os_package_resolver = os_package_resolver
            @manifest = Manifest.new(self, os_package_resolver: os_package_resolver)
            @config = Configuration.new(config_file_path)

            @os_package_installer = OSPackageInstaller.new(
                self, os_package_resolver, package_managers: package_managers)
            super(root_dir)
        end

        # Returns the root of the current autoproj workspace
        #
        # @return [String,nil] the root path, or nil if one did not yet source
        #   the workspace's env.sh
        def self.autoproj_current_root
            if env = ENV['AUTOPROJ_CURRENT_ROOT']
                if !env.empty?
                    env
                end
            end
        end

        # Returns the workspace the current directory is part of
        #
        # @return [Workspace]
        # @raise (see from_dir)
        def self.from_pwd(**workspace_options)
            from_dir(Dir.pwd, **workspace_options)
        end

        # Returns the workspace a directory is part of
        #
        # @return [Workspace]
        # @raise [MismatchingWorkspace] if the currently loaded env.sh
        #   and the one from +dir+ mismatch
        # @raise [NotWorkspace] if dir is not within an autoproj workspace
        def self.from_dir(dir, **workspace_options)
            if path = Autoproj.find_workspace_dir(dir)
                Workspace.new(path, **workspace_options)
            elsif Autoproj.find_v1_workspace_dir(dir)
                raise OutdatedWorkspace, "#{dir} looks like a v1 workspace, run autoproj upgrade before continuing"
            else
                raise NotWorkspace, "not in a Autoproj installation"
            end
        end

        def self.from_environment(**workspace_options)
            if path = Autoproj.find_workspace_dir
                from_dir(path, **workspace_options)
            elsif Autoproj.find_v1_workspace_dir(dir = Autoproj.default_find_base_dir)
                raise OutdatedWorkspace, "#{dir} looks like a v1 workspace, run autoproj upgrade before continuing"
            elsif envvar = ENV['AUTOPROJ_CURRENT_ROOT']
                raise NotWorkspace, "AUTOPROJ_CURRENT_ROOT is currently set to #{envvar}, but that is not an Autoproj workspace"
            else
                raise NotWorkspace, "not in an Autoproj installation, and no env.sh has been loaded so far"
            end
        end

        # Tests whether the given path is under a directory tree managed by
        # autoproj
        def self.in_autoproj_project?(path)
            !!Autoproj.find_workspace_dir(path)
        end

        # Returns the default workspace
        #
        # It uses the AUTOPROJ_CURRENT_ROOT environment variable if available,
        # falling back to the current directory
        #
        # @raise MismatchingWorkspace if the workspace pointed by
        # AUTOPROJ_CURRENT_ROOT does not match the one containing the current
        # directory
        def self.default(**workspace_options)
            ws = from_environment(**workspace_options)
            if (from_pwd = Autoproj.find_workspace_dir(Dir.pwd)) && (from_pwd != ws.root_dir)
                raise MismatchingWorkspace, "the current environment points to #{ws.root_dir}, but you are in #{from_pwd}, make sure you are loading the right #{ENV_FILENAME} script !"
            end
            ws
        end

        def load(*args)
            set_as_main_workspace
            flag, Autoproj.warn_deprecated_level = Autoproj.warn_deprecated_level, 1
            super
        ensure
            Autoproj.warn_deprecated_level = flag
        end

        # Returns the configuration directory for this autoproj installation.
        #
        # @return [String]
        def config_dir
            File.join(root_dir, 'autoproj')
        end

        # The directory under which autoproj saves all its internal
        # configuration and files
        def dot_autoproj_dir
            File.join(root_dir, '.autoproj')
        end

        # The installation manifest
        def installation_manifest_path
            InstallationManifest.path_for_workspace_root(root_dir)
        end

        # The path to the workspace configuration file
        def config_file_path
            File.join(dot_autoproj_dir, 'config.yml')
        end

        # The path to the workspace's manifest file
        def manifest_file_path
            File.join(root_dir, 'autoproj', config.get('manifest_name', 'manifest'))
        end

        # Return the directory in which remote package set definition should be
        # checked out
        def remotes_dir
            File.join(dot_autoproj_dir, "remotes")
        end

        # (see Configuration#prefix_dir)
        def prefix_dir
            File.expand_path(config.prefix_dir, root_dir)
        end

        # Change {prefix_dir}
        def prefix_dir=(path)
            config.prefix_dir = path
        end

        # (see Configuration#build_dir)
        def build_dir
            config.build_dir
        end

        # Change {#build_dir}
        def build_dir=(path)
            config.set 'build', path, true
        end

        def log_dir
            File.join(prefix_dir, 'log')
        end

        OVERRIDES_DIR = "overrides.d"

        # Returns the directory containing overrides files
        #
        # @return [String]
        def overrides_dir
            File.join(config_dir, OVERRIDES_DIR)
        end

        def load_config(reconfigure = false)
            @config = Configuration.new(config_file_path)
            if File.file?(config_file_path)
                config.load(reconfigure: reconfigure)
                if raw_vcs = config.get('manifest_source', nil)
                    manifest.vcs = VCSDefinition.from_raw(raw_vcs)
                else
                    manifest.vcs = VCSDefinition.from_raw(
                        type: 'local', url: config_dir)
                end
                os_package_resolver.prefer_indep_over_os_packages = config.prefer_indep_over_os_packages?
                os_package_resolver.operating_system ||= config.get('operating_system', nil)
            end
            @config
        end

        def save_config
            config.save(config_file_path)
        end

        def autodetect_operating_system(force: false)
            if force || !os_package_resolver.operating_system
                begin
                    Autobuild.progress_start :operating_system_autodetection,
                        "autodetecting the operating system"
                    names, versions = OSPackageResolver.autodetect_operating_system
                    os_package_resolver.operating_system = [names, versions]
                    Autobuild.progress :operating_system_autodetection,
                        "operating system: #{(names - ['default']).join(",")} - #{(versions - ['default']).join(",")}"
                ensure
                    Autobuild.progress_done :operating_system_autodetection
                end
                config.set('operating_system', os_package_resolver.operating_system, true)
            end
        end

        def operating_system
            os_package_resolver.operating_system
        end

        def supported_operating_system?
            os_package_resolver.supported_operating_system?
        end

        def setup_os_package_installer
            autodetect_operating_system
            os_package_installer.each_manager do |pkg_mng|
                pkg_mng.initialize_environment
            end
            os_package_resolver.load_default
            os_package_installer.define_osdeps_mode_option
            os_package_installer.osdeps_mode
        end

        def setup_ruby_version_handling
            os_package_resolver.add_aliases('ruby' => ruby_version_keyword)
            osdep_suffixes << ruby_version_keyword
        end

        def setup
            setup_ruby_version_handling
            migrate_bundler_and_autoproj_gem_layout
            load_config
            rewrite_shims
            autodetect_operating_system
            config.validate_ruby_executable
            config.apply_autobuild_configuration
            load_autoprojrc
            load_main_initrb
            config.each_reused_autoproj_installation do |p|
                manifest.reuse(p)
            end
            if File.exist?(manifest_file_path)
                manifest.load(manifest_file_path)
            end

            Autobuild.prefix = prefix_dir
            FileUtils.mkdir_p File.join(prefix_dir, '.autoproj')
            File.open(File.join(prefix_dir, '.autoproj', 'config.yml'), 'w') do |io|
                io.puts "workspace: \"#{root_dir}\""
            end

            Autobuild.srcdir = root_dir
            Autobuild.logdir = log_dir
            if cache_dir = config.importer_cache_dir
                Autobuild::Importer.default_cache_dirs = cache_dir
            end
            setup_os_package_installer
            install_ruby_shims
        end

        def install_ruby_shims
            install_suffix = ""
            if match = /ruby(.*)$/.match(RbConfig::CONFIG['RUBY_INSTALL_NAME'])
                install_suffix = match[1]
            end

            bindir = File.join(prefix_dir, 'bin')
            FileUtils.mkdir_p bindir
            env.add 'PATH', bindir

            File.open(File.join(bindir, 'ruby'), 'w') do |io|
                io.puts "#! /bin/sh"
                io.puts "exec #{config.ruby_executable} \"$@\""
            end
            FileUtils.chmod 0755, File.join(bindir, 'ruby')

            ['gem', 'irb', 'testrb'].each do |name|
                # Look for the corresponding gem program
                prg_name = "#{name}#{install_suffix}"
                if File.file?(prg_path = File.join(RbConfig::CONFIG['bindir'], prg_name))
                    File.open(File.join(bindir, name), 'w') do |io|
                        io.puts "#! #{config.ruby_executable}"
                        io.puts "exec \"#{prg_path}\", *ARGV"
                    end
                    FileUtils.chmod 0755, File.join(bindir, name)
                end
            end
        end

        def rewrite_shims
            gemfile  = File.join(dot_autoproj_dir, 'Gemfile')
            binstubs = File.join(dot_autoproj_dir, 'bin')
            Ops::Install.rewrite_shims(binstubs, config.ruby_executable, gemfile, config.gems_gem_home)
        end

        def update_bundler
            require 'autoproj/ops/install'
            gem_program = Ops::Install.guess_gem_program
            install = Ops::Install.new(root_dir)
            Autoproj.message "  updating bundler"
            install.install_bundler(gem_program, silent: true)
        end

        def update_autoproj(restart_on_update: true)
            config.validate_ruby_executable

            # This is a guard to avoid infinite recursion in case the user is
            # running autoproj osdeps --force
            if ENV['AUTOPROJ_RESTARTING'] == '1'
                return
            end

            gemfile  = File.join(dot_autoproj_dir, 'Gemfile')
            binstubs = File.join(dot_autoproj_dir, 'bin')
            if restart_on_update
                old_autoproj_path = PackageManagers::BundlerManager.bundle_gem_path(
                    self, 'autoproj', gemfile: gemfile)
            end
            begin
                Autoproj.message "  updating autoproj"
                PackageManagers::BundlerManager.run_bundler_install(
                    self, gemfile, binstubs: binstubs)
            ensure
                Ops::Install.rewrite_shims(binstubs, config.ruby_executable, gemfile, config.gems_gem_home)
            end
            if restart_on_update
                new_autoproj_path = PackageManagers::BundlerManager.bundle_gem_path(
                    self, 'autoproj', gemfile: gemfile)
            end

            # First things first, see if we need to update ourselves
            if new_autoproj_path != old_autoproj_path
                puts
                Autoproj.message "autoproj has been updated, restarting"
                puts

                # We updated autobuild or autoproj themselves ... Restart !
                #
                # ...But first save the configuration (!)
                config.save
                ENV['AUTOPROJ_RESTARTING'] = '1'
                require 'rbconfig'
                exec(config.ruby_executable, $0, *ARGV)
            end
        end

        def run(*args, &block)
            if args.last.kind_of?(Hash)
                options = args.pop
            else options = Hash.new
            end
            options_env = options.fetch(:env, Hash.new)
            options[:env] = env.resolved_env.merge(options_env)
            Autobuild::Subprocess.run(*args, options, &block)
        end

        def migrate_bundler_and_autoproj_gem_layout
            if !File.directory?(File.join(dot_autoproj_dir, 'autoproj'))
                return
            else
                config = YAML.load(File.read(File.join(dot_autoproj_dir, 'config.yml')))
                return if config['gems_install_path']
            end

            Autoproj.silent = false
            Autoproj.warn "The way bundler and autoproj are installed changed"
            Autoproj.warn "You must download"
            Autoproj.warn "   https://raw.githubusercontent.com/rock-core/autoproj/master/bin/autoproj_install"
            Autoproj.warn "and run it at the root of this workspace"
            exit 2
        end

        def set_as_main_workspace
            Autoproj.workspace = self
            Autoproj.root_dir = root_dir
            Autobuild.env = env

            if block_given?
                begin
                    yield
                ensure 
                    clear_main_workspace
                end
            end
        end

        def clear_main_workspace
            Autoproj.workspace = nil
            Autoproj.root_dir = nil
            Autobuild.env = nil
        end

        # Loads autoproj/init.rb
        #
        # This is included in {setup}
        def load_main_initrb
            set_as_main_workspace

            local_source = manifest.main_package_set
            load_if_present(local_source, config_dir, "init.rb")
        end

        # Loads the .autoprojrc file
        #
        # This is included in {setup}
        def load_autoprojrc
            set_as_main_workspace

            # Load the user-wide autoproj RC file
            home_dir =
                begin Dir.home
                rescue ArgumentError
                end

            if home_dir
                rcfile = File.join(home_dir, '.autoprojrc')
                if File.file?(rcfile)
                    Kernel.load rcfile
                end
            end
        end

        def load_package_sets(only_local: false,
                              checkout_only: true,
                              reconfigure: false,
                              keep_going: false,
                              mainline: nil,
                              reset: false,
                              retry_count: nil)
            if !File.file?(manifest_file_path) # empty install, just return
                return
            end

            Ops::Configuration.new(self).
                load_package_sets(only_local: only_local,
                                  checkout_only: checkout_only,
                                  keep_going: keep_going,
                                  reset: reset,
                                  retry_count: retry_count,
                                  mainline: mainline)
        end

        def load_packages(selection = manifest.default_packages(false), options = Hash.new)
            options = Hash[warn_about_ignored_packages: true, checkout_only: true].
                merge(options)
            ops = Ops::Import.new(self)
            ops.import_packages(selection, options)
        end
        
        def setup_all_package_directories
            # Override the package directories from our reused installations
            imported_packages = Set.new
            manifest.reused_installations.each do |imported_manifest|
                imported_manifest.each do |imported_pkg|
                    imported_packages << imported_pkg.name
                    if pkg = manifest.find_package_definition(imported_pkg.name)
                        pkg.autobuild.srcdir = imported_pkg.srcdir
                        pkg.autobuild.prefix = imported_pkg.prefix
                    end
                end
            end

            manifest.each_package_definition do |pkg_def|
                pkg = pkg_def.autobuild
                next if imported_packages.include?(pkg_def.name)
                setup_package_directories(pkg)
            end
        end

        def setup_package_directories(pkg)
            pkg_name = pkg.name

            layout =
                if config.randomize_layout?
                    Digest::SHA256.hexdigest(pkg_name)[0, 12]
                else manifest.whereis(pkg_name)
                end

            srcdir =
                if target = manifest.moved_packages[pkg_name]
                    File.join(layout, target)
                else
                    File.join(layout, pkg_name)
                end

            prefixdir =
                if config.separate_prefixes?
                    pkg_name
                else
                    layout
                end

            pkg = manifest.find_autobuild_package(pkg_name)
            pkg.srcdir = File.join(root_dir, srcdir)
            if pkg.respond_to?(:builddir)
                pkg.builddir = compute_builddir(pkg)
            end

            pkg.prefix = File.join(prefix_dir, prefixdir)
            pkg.doc_target_dir = File.join(prefix_dir, 'doc', pkg_name)
            pkg.logdir = File.join(pkg.prefix, "log")
        end
        
        def compute_builddir(pkg)
            # If we're given an absolute build dir, we have to append the
            # package name to it to make it unique
            if Pathname.new(build_dir).absolute?
                File.join(build_dir, pkg.name)
            else
                build_dir
            end
        end

        # Finalizes the configuration loading
        #
        # This must be done before before we run any dependency-sensitive
        # operation (e.g. import)
        def finalize_package_setup
            set_as_main_workspace
            # Now call the blocks that the user defined in the autobuild files. We do it
            # now so that the various package directories are properly setup
            manifest.each_package_definition do |pkg|
                pkg.user_blocks.each do |blk|
                    blk[pkg.autobuild]
                end
                pkg.setup = true
            end

            manifest.each_package_set do |source|
                if source.local_dir
                    load_if_present(source, source.local_dir, "overrides.rb")
                end
            end

            main_package_set = manifest.main_package_set
            Dir.glob(File.join( overrides_dir, "*.rb" ) ).sort.each do |file|
                load main_package_set, file
            end
        end

        # Finalizes the complete setup
        #
        # This must be done after all ignores/excludes and package selection
        # have been properly set up (a.k.a. after package import)
        def finalize_setup
            # Finally, disable all ignored packages on the autobuild side
            manifest.each_ignored_package do |pkg|
                pkg.disable
            end

            # We now have processed the process setup blocks. All configuration
            # should be done and we can save the configuration data.
            config.save
        end

        def all_present_packages
            manifest.each_autobuild_package.
                find_all { |pkg| File.directory?(pkg.srcdir) }.
                map(&:name)
        end

        # Update this workspace's installation manifest
        #
        # @param [Array<String>] package_names the name of the packages that
        #   should be updated
        def export_installation_manifest
            selected_packages = manifest.all_selected_source_packages
            install_manifest = InstallationManifest.new(installation_manifest_path)

            # Update the new entries
            manifest.each_package_set do |pkg_set|
                next if pkg_set.main?
                install_manifest.add_package_set(pkg_set)
            end
            selected_packages.each do |pkg_name|
                pkg = manifest.package_definition_by_name(pkg_name)
                install_manifest.add_package(pkg)
            end
            # And save
            install_manifest.save
        end

        # Export the workspace's env.sh file
        def export_env_sh(package_names = all_present_packages, shell_helpers: true)
            env = self.env.dup
            manifest.all_selected_source_packages.each do |pkg|
                pkg.autobuild.apply_env(env)
            end
            env.export_env_sh(shell_helpers: shell_helpers)
        end

        def pristine_os_packages(packages, options = Hash.new)
            os_package_installer.pristine(packages, options)
        end

        # Returns the list of all OS packages required by the state of the
        # workspace
        #
        # @return [Array<String>] the list of OS packages that can be fed to
        #   {OSPackageManager#install}
        def all_os_packages(import_missing: false, parallel: config.parallel_import_level)
            if import_missing
                ops = Autoproj::Ops::Import.new(self)
                _, all_os_packages =
                    ops.import_packages(manifest.default_packages,
                                    checkout_only: true, only_local: true, reset: false,
                                    recursive: true, keep_going: true, parallel: parallel,
                                    retry_count: 0)
                all_os_packages
            else
                result = Set.new
                manifest.all_selected_source_packages.each do |source_package|
                    result.merge(source_package.autobuild.os_packages)
                end
                result
            end
        end

        def install_os_packages(packages, all: all_os_packages, **options)
            os_package_installer.install(packages, all: all, **options)
        end

        # Define and register an autobuild package on this workspace
        #
        # @param [Symbol] package_type a package-creation method on {Autobuild},
        #   e.g. :cmake
        # @param [String] package_name the package name
        # @param [PackageSet] package_set the package set into which this
        #   package is defined
        # @param [String,nil] file the path to the file that defines this
        #   package (used for error reporting)
        # @param [Proc,nil] block a setup block that should be called to
        #   configure the package
        # @return [PackageDefinition]
        def define_package(package_type, package_name, block = nil, package_set = manifest.main_package_set, file = nil)
            autobuild_package = Autobuild.send(package_type, package_name)
            register_package(autobuild_package, block, package_set, file)
        end

        # Register an autobuild package on this workspace
        #
        # @param [Autobuild::Package] package
        # @param [PackageSet] package_set the package set into which this
        #   package is defined
        # @param [String,nil] file the path to the file that defines this
        #   package (used for error reporting)
        # @param [Proc,nil] block a setup block that should be called to
        #   configure the package
        # @return [PackageDefinition]
        def register_package(package, block = nil, package_set = manifest.main_package_set, file = nil)
            pkg = manifest.register_package(package, block, package_set, file)
            pkg.autobuild.ws = self
            pkg
        end
    end

    def self.workspace
        @workspace ||= Workspace.new(root_dir)
    end

    def self.workspace=(ws)
        @workspace = ws
        if ws
            self.root_dir = ws.root_dir
        end
    end

    def self.env
        workspace.env
    end
end

