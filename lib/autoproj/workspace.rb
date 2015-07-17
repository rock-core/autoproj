require 'autoproj/ops/import'

module Autoproj
    class Workspace < Ops::Loader
        attr_reader :root_dir

        attr_reader :config
        attr_reader :env
        attr_reader :manifest
        attr_reader :loader

        def initialize(root_dir)
            @root_dir = root_dir
            @loader = loader
            @env = Environment.new
            @manifest = Manifest.new
            Autobuild.env = nil
            env.prepare(root_dir)

            super(root_dir)
        end

        def self.autoproj_current_root
            if env = ENV['AUTOPROJ_CURRENT_ROOT']
                if !env.empty?
                    env
                end
            end
        end

        def self.from_pwd
            from_dir(Dir.pwd)
        end

        def self.from_dir(dir)
            if path = find_root_dir(dir)
                # Make sure that the currently loaded env.sh is actually us
                env = autoproj_current_root
                if env && env != path
                    raise UserError, "the current environment is for #{env}, but you are in #{path}, make sure you are loading the right #{ENV_FILENAME} script !"
                end
                Workspace.new(path)
            else
                raise UserError, "not in a Autoproj installation"
            end
        end

        def self.from_environment
            if path = (find_root_dir || autoproj_current_root)
                from_dir(path)
            else
                raise UserError, "not in an Autoproj installation, and no env.sh has been loaded so far"
            end
        end

        def self.find_root_dir(base_dir = Dir.pwd)
            path = Pathname.new(base_dir)
            while !path.root?
                if (path + "autoproj" + 'manifest').file?
                    break
                end
                path = path.parent
            end

            if path.root?
                return
            end

            result = path.to_s

            # I don't know if this is still useful or not ... but it does not hurt
            #
            # Preventing backslashed in path, that might be confusing on some path compares
            if Autobuild.windows?
                result = result.gsub(/\\/,'/')
            end
            result
        end

        def osdeps
            manifest.osdeps
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

        # Return the directory in which remote package set definition should be
        # checked out
        def remotes_dir
            File.join(root_dir, ".remotes")
        end

        # (see Configuration#prefix_dir)
        def prefix_dir
            File.expand_path(config.prefix_dir, root_dir)
        end

        # Change {prefix_dir}
        def prefix_dir=(path)
            config.set 'prefix', path, true
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
            config_path = File.join(config_dir, 'config.yml')
            @config = Configuration.new(config_path)
            if File.file?(config_path)
                config.load(reconfigure: reconfigure)
                manifest.vcs = VCSDefinition.from_raw(config.get('manifest_source', nil))
            end
        end

        def load_manifest
            manifest_path = File.join(config_dir, 'manifest')
            if File.exists?(manifest_path)
                manifest.load(manifest_path)
            end
        end

        def setup
            load_config
            config.validate_ruby_executable
            config.apply_autobuild_configuration
            load_autoprojrc
            load_main_initrb
            config.each_reused_autoproj_installation do |p|
                manifest.reuse(p)
            end
            load_manifest

            Autobuild.prefix = prefix_dir
            Autobuild.srcdir = root_dir
            Autobuild.logdir = log_dir
            env.prepare(root_dir)
            Autoproj::OSDependencies::PACKAGE_HANDLERS.each do |pkg_mng|
                pkg_mng.initialize_environment(env, manifest, root_dir)
            end

            Autoproj::OSDependencies.define_osdeps_mode_option(config)
            osdeps.load_default
            osdeps.osdeps_mode
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

        def update_autoproj(options = Hash.new)
            options = validate_options options,
                force: false, restart_on_update: true
            return if !options[:force]

            config.validate_ruby_executable

            # This is a guard to avoid infinite recursion in case the user is
            # running autoproj osdeps --force
            if ENV['AUTOPROJ_RESTARTING'] == '1'
                return
            end

            did_update =
                begin
                    saved_flag = PackageManagers::GemManager.with_prerelease
                    PackageManagers::GemManager.with_prerelease = Autoproj.config.use_prerelease?
                    osdeps.install(%w{autobuild autoproj})
                ensure
                    PackageManagers::GemManager.with_prerelease = saved_flag
                end

            # First things first, see if we need to update ourselves
            if did_update && options[:restart_on_update]
                puts
                Autoproj.message 'autoproj and/or autobuild has been updated, restarting autoproj'
                puts

                # We updated autobuild or autoproj themselves ... Restart !
                #
                # ...But first save the configuration (!)
                config.save
                ENV['AUTOPROJ_RESTARTING'] = '1'
                require 'rbconfig'
                exec(ruby_executable, $0, *argv)
            end
        end

        def set_as_main_workspace
            Autoproj.workspace = self
            Autoproj.root_dir = root_dir
            Autobuild.env = env
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

        # Load OS dependency information contained in our registered package
        # sets into the provided osdep object
        #
        # This is included in {load_package_sets}
        #
        # @param [OSDependencies] osdeps the osdep handling object
        # @return [void]
        def load_osdeps_from_package_sets
            manifest.each_osdeps_file do |pkg_set, file|
                osdeps.merge(pkg_set.load_osdeps(file))
            end
        end

        def load_package_sets(options = Hash.new)
            options = validate_options options,
                only_local: false,
                checkout_only: true,
                silent: false, # NOTE: this is ignored, enclose call with Autoproj.silent { }
                reconfigure: false,
                ignore_errors: false,
                mainline: nil

            Ops::Configuration.new(self).
                load_package_sets(only_local: options[:only_local],
                                  checkout_only: options[:checkout_only],
                                  ignore_errors: options[:ignore_errors])

            manifest.each_package_set do |pkg_set|
                if Gem::Version.new(pkg_set.required_autoproj_version) > Gem::Version.new(Autoproj::VERSION)
                    raise ConfigError.new(pkg_set.source_file), "the #{pkg_set.name} package set requires autoproj v#{pkg_set.required_autoproj_version} but this is v#{Autoproj::VERSION}"
                end
            end

            # Loads OS package definitions once and for all
            load_osdeps_from_package_sets
            # And exclude any package that is not available on this particular
            # configuration
            mark_unavailable_osdeps_as_excluded

            # Load the required autobuild definitions
            Autoproj.message("autoproj: loading ...", :bold)
            if !options[:reconfigure]
                Autoproj.message("run 'autoproj reconfigure' to change configuration options", :bold)
                Autoproj.message("and use 'autoproj switch-config' to change the remote source for", :bold)
                Autoproj.message("autoproj's main build configuration", :bold)
            end
            manifest.each_autobuild_file do |source, name|
                import_autobuild_file source, name
            end

            # Now, load the package's importer configurations (from the various
            # source.yml files)
            mainline = options[:mainline]
            if mainline.respond_to?(:to_str)
                mainline = manifest.package_set(mainline)
            end
            manifest.load_importers(mainline: mainline)

            # Auto-add packages that are
            #  * present on disk
            #  * listed in the layout part of the manifest
            #  * but have no definition
            explicit = manifest.normalized_layout
            explicit.each do |pkg_or_set, layout_level|
                next if manifest.find_autobuild_package(pkg_or_set)
                next if manifest.has_package_set?(pkg_or_set)

                # This is not known. Check if we can auto-add it
                full_path = File.expand_path(File.join(Autoproj.root_dir, layout_level, pkg_or_set))
                next if !File.directory?(full_path)

                handler, srcdir = Autoproj.package_handler_for(full_path)
                if handler
                    Autoproj.message "  auto-adding #{pkg_or_set} #{"in #{layout_level} " if layout_level != "/"}using the #{handler.gsub(/_package/, '')} package handler"
                    in_package_set(manifest.local_package_set, manifest.file) do
                        send(handler, pkg_or_set)
                    end
                else
                    Autoproj.warn "cannot auto-add #{pkg_or_set}: unknown package type"
                end
            end

            manifest.each_autobuild_package do |pkg|
                Autobuild.each_utility do |uname, _|
                    pkg.utility(uname).enabled =
                        config.utility_enabled_for?(uname, pkg.name)
                end
            end

            # We finished loading the configuration files. Not all configuration
            # is done (since we need to process the package setup blocks), but
            # save the current state of the configuration anyway.
            config.save
        end

        def mark_unavailable_osdeps_as_excluded
            osdeps.all_package_names.each do |osdep_name|
                # If the osdep can be replaced by source packages, there's
                # nothing to do really. The exclusions of the source packages
                # will work as expected
                if manifest.osdeps_overrides[osdep_name] || manifest.find_autobuild_package(osdep_name)
                    next
                end

                case availability = osdeps.availability_of(osdep_name)
                when OSDependencies::UNKNOWN_OS
                    manifest.add_exclusion(osdep_name, "this operating system is unknown to autoproj")
                when OSDependencies::WRONG_OS
                    manifest.add_exclusion(osdep_name, "there are definitions for it, but not for this operating system")
                when OSDependencies::NONEXISTENT
                    manifest.add_exclusion(osdep_name, "it is marked as unavailable for this operating system")
                end
            end
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
                    if pkg = manifest.find_package(imported_pkg.name)
                        pkg.autobuild.srcdir = imported_pkg.srcdir
                        pkg.autobuild.prefix = imported_pkg.prefix
                    end
                end
            end

            manifest.packages.each_value do |pkg_def|
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
                # If we're given an absolute build dir, we have to append the
                # package name to it to make it unique
                if Pathname.new(build_dir).absolute?
                    pkg.builddir = File.join(build_dir, pkg_name)
                else
                    pkg.builddir = build_dir
                end
            end

            pkg.prefix = File.join(prefix_dir, prefixdir)
            pkg.doc_target_dir = File.join(prefix_dir, 'doc', pkg_name)
            pkg.logdir = File.join(pkg.prefix, "log")
        end

        # Finalizes the configuration loading
        #
        # This must be done before before we run any dependency-sensitive
        # operation (e.g. import)
        def finalize_package_setup
            set_as_main_workspace
            # Now call the blocks that the user defined in the autobuild files. We do it
            # now so that the various package directories are properly setup
            manifest.packages.each_value do |pkg|
                pkg.user_blocks.each do |blk|
                    blk[pkg.autobuild]
                end
                pkg.setup = true
            end

            manifest.each_package_set do |source|
                load_if_present(source, source.local_dir, "overrides.rb")
            end

            Dir.glob(File.join( Autoproj.overrides_dir, "*.rb" ) ).sort.each do |file|
                load file
            end
        end

        # Finalizes the complete setup
        #
        # This must be done after all ignores/excludes and package selection
        # have been properly set up (a.k.a. after package import)
        def finalize_setup
            # Finally, disable all ignored packages on the autobuild side
            manifest.each_ignored_package do |pkg_name|
                pkg = manifest.find_autobuild_package(pkg_name)
                if !pkg
                    Autoproj.warn "ignore line #{pkg_name} does not match anything"
                else
                    pkg.disable
                end
            end

            setup_environment_from_packages

            # We now have processed the process setup blocks. All configuration
            # should be done and we can save the configuration data.
            config.save
        end

        def setup_environment_from_packages
            set_as_main_workspace
            manifest.reused_installations.each do |reused_manifest|
                reused_manifest.each do |pkg|
                    # The reused installations might have packages we do not
                    # know about, just ignore them
                    if pkg = manifest.find_autobuild_package(pkg)
                        pkg.update_environment
                    end
                end
            end

            # Make sure that we have the environment of all selected packages
            manifest.all_selected_packages(false).each do |pkg_name|
                manifest.find_autobuild_package(pkg_name).update_environment
            end
        end

        def export_installation_manifest
            File.open(File.join(root_dir, ".autoproj-installation-manifest"), 'w') do |io|
                manifest.all_selected_packages(false).each do |pkg_name|
                    if pkg = manifest.find_autobuild_package(pkg_name)
                        io.puts "#{pkg_name},#{pkg.srcdir},#{pkg.prefix}"
                    end
                end
            end
        end
    end

    def self.workspace
        @workspace ||= Workspace.new(root_dir)
    end

    def self.workspace=(ws)
        @workspace = ws
    end

    def self.env
        workspace.env
    end
end

