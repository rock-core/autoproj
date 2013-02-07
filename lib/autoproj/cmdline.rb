require 'highline'
require 'utilrb/module/attr_predicate'
module Autoproj
    class << self
        attr_accessor :verbose
        attr_reader :console
        def silent?
            Autobuild.silent?
        end
        def silent=(value)
            Autobuild.silent = value
        end
    end
    @verbose = false
    @console = HighLine.new
    ENV_FILENAME =
        if Autobuild.windows? then "env.bat"
        else "env.sh"
        end
	

    def self.silent(&block)
        Autobuild.silent(&block)
    end

    def self.message(*args)
        Autobuild.message(*args)
    end

    def self.color(*args)
        Autobuild.color(*args)
    end

    # Displays an error message
    def self.error(message)
        Autobuild.error(message)
    end

    # Displays a warning message
    def self.warn(message)
        Autobuild.warn(message)
    end

    module CmdLine
        class << self
            attr_reader :ruby_executable
        end

        def self.handle_ruby_version
            ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
            ruby_bindir = RbConfig::CONFIG['bindir']

            @ruby_executable = File.join(ruby_bindir, ruby)
            if Autoproj.has_config_key?('ruby_executable')
                expected = Autoproj.user_config('ruby_executable')
                if expected != ruby_executable
                    raise ConfigError.new, "this autoproj installation was bootstrapped using #{expected}, but you are currently running under #{ruby_executable}. This is usually caused by calling a wrong gem program (for instance, gem1.8 instead of gem1.9.1)"
                end
            end
            Autoproj.change_option('ruby_executable', ruby_executable, true)

            install_suffix = ""
            if match = /ruby(.*)$/.match(ruby)
                install_suffix = match[1]
            end

            bindir = File.join(Autoproj.build_dir, 'bin')
            FileUtils.mkdir_p bindir
            Autoproj.env_add 'PATH', bindir

            File.open(File.join(bindir, 'ruby'), 'w') do |io|
                io.puts "#! /bin/sh"
                io.puts "exec #{File.join(ruby_bindir, ruby)} \"$@\""
            end
            FileUtils.chmod 0755, File.join(bindir, 'ruby')

            subprograms = ['gem', 'irb'].each do |name|
                # Look for the corresponding gem program
                prg_name = "#{name}#{install_suffix}"
                if File.file?(prg_path = File.join(ruby_bindir, prg_name))
                    File.open(File.join(bindir, name), 'w') do |io|
                        io.puts "#! /bin/sh"
                        io.puts "exec #{prg_path} \"$@\""
                    end
                end
            end
        end

        def self.initialize
            if defined? Encoding # This is a 1.9-only thing
                Encoding.default_internal = Encoding::UTF_8
                Encoding.default_external = Encoding::UTF_8
            end

            Autobuild::Reporting << Autoproj::Reporter.new
            if mail_config[:to]
                Autobuild::Reporting << Autobuild::MailReporter.new(mail_config)
            end

            # Remove from LOADED_FEATURES everything that is coming from our
            # configuration directory
            Autobuild::Package.clear
            Autoproj.loaded_autobuild_files.clear
            Autoproj.load_config

            handle_ruby_version

            if Autoproj.has_config_key?('autobuild')
                params = Autoproj.user_config('autobuild')
                if params.kind_of?(Hash)
                    params.each do |k, v|
                        Autobuild.send("#{k}=", v)
                    end
                end
            end

            if Autoproj.has_config_key?('prefix')
                Autoproj.prefix = Autoproj.user_config('prefix')
            end

            if Autoproj.has_config_key?('randomize_layout')
                @randomize_layout = Autoproj.user_config('randomize_layout')
            end

            # If we are under rubygems, check that the GEM_HOME is right ...
            if $LOADED_FEATURES.any? { |l| l =~ /rubygems/ }
                if ENV['GEM_HOME'] != Autoproj.gem_home
                    raise ConfigError.new, "RubyGems is already loaded with a different GEM_HOME, make sure you are loading the right #{ENV_FILENAME} script !"
                end
            end

            # Set up some important autobuild parameters
            Autoproj.env_inherit 'PATH', 'PKG_CONFIG_PATH', 'RUBYLIB', 'LD_LIBRARY_PATH', 'GEM_PATH', 'CMAKE_PREFIX_PATH', 'PYTHONPATH'
            Autoproj.env_set 'GEM_HOME', Autoproj.gem_home
            Autoproj.env_add 'GEM_PATH', Autoproj.gem_home
            Autoproj.env_add 'PATH', File.join(Autoproj.gem_home, 'bin')
            Autoproj.env_set 'RUBYOPT', "-rubygems"
            Autobuild.prefix  = Autoproj.build_dir
            Autobuild.srcdir  = Autoproj.root_dir
            Autobuild.logdir = File.join(Autobuild.prefix, 'log')

            Autoproj.manifest = Manifest.new

            local_source = LocalPackageSet.new(Autoproj.manifest)

            home_dir =
                if Dir.respond_to?(:home) # 1.9 specific
                    Dir.home
                else ENV['HOME']
                end
            # Load the user-wide autoproj RC file
            if home_dir
                Autoproj.load_if_present(local_source, home_dir, ".autoprojrc")
            end

            # We load the local init.rb first so that the manifest loading
            # process can use options defined there for the autoproj version
            # control information (for instance)
            Autoproj.load_if_present(local_source, local_source.local_dir, "init.rb")

            manifest_path = File.join(Autoproj.config_dir, 'manifest')
            Autoproj.manifest.load(manifest_path)

            # Once thing left to do: handle the Autoproj.auto_update
            # configuration parameter. This has to be done here as the rest of
            # the configuration update/loading procedure rely on it.
            #
            # Namely, we must check if Autobuild.do_update has been explicitely
            # set to true or false. If that is the case, don't do anything.
            # Otherwise, set it to the value of auto_update (set in the
            # manifest)
            if Autobuild.do_update.nil?
                Autobuild.do_update = manifest.auto_update?
            end
            if @update_os_dependencies.nil?
                @update_os_dependencies = manifest.auto_update?
            end

            # Initialize the Autoproj.osdeps object by loading the default. The
            # rest is loaded later
            Autoproj.osdeps = Autoproj::OSDependencies.load_default
            Autoproj.osdeps.silent = !osdeps?
            Autoproj.osdeps.filter_uptodate_packages = osdeps_filter_uptodate?
            if osdeps_forced_mode
                Autoproj.osdeps.osdeps_mode = osdeps_forced_mode
            end

            # Define the option NOW, as update_os_dependencies? needs to know in
            # what mode we are.
            #
            # It might lead to having multiple operating system detections, but
            # that's the best I can do for now.
	    Autoproj::OSDependencies.define_osdeps_mode_option
            Autoproj.osdeps.osdeps_mode

            # Do that AFTER we have properly setup Autoproj.osdeps as to avoid
            # unnecessarily redetecting the operating system
            if update_os_dependencies? || osdeps?
                Autoproj.change_option('operating_system', Autoproj::OSDependencies.operating_system(:force => true), true)
            end
        end

        def self.update_myself
            return if !Autoproj::CmdLine.update_os_dependencies?

            # This is a guard to avoid infinite recursion in case the user is
            # running autoproj osdeps --force
            if ENV['AUTOPROJ_RESTARTING'] == '1'
                return
            end

            # First things first, see if we need to update ourselves
            if Autoproj.osdeps.install(%w{autobuild autoproj})
                puts
                Autoproj.message 'autoproj and/or autobuild has been updated, restarting autoproj'
                puts

                # We updated autobuild or autoproj themselves ... Restart !
                #
                # ...But first save the configuration (!)
                Autoproj.save_config
                ENV['AUTOPROJ_RESTARTING'] = '1'
                require 'rbconfig'
                ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                if defined?(ORIGINAL_ARGV)
                    exec(ruby, $0, *ORIGINAL_ARGV)
                else
                    exec(ruby, $0, *ARGV)
                end
            end
        end

        def self.load_configuration(silent = false)
            manifest = Autoproj.manifest
            manifest.cache_package_sets

            manifest.each_package_set(false) do |pkg_set|
                if Gem::Version.new(pkg_set.required_autoproj_version) > Gem::Version.new(Autoproj::VERSION)
                    raise ConfigError.new(pkg_set.source_file), "the #{pkg_set.name} package set requires autoproj v#{pkg_set.required_autoproj_version} but this is v#{Autoproj::VERSION}"
                end
            end

            # Load init.rb files. each_source must not load the source.yml file, as
            # init.rb may define configuration options that are used there
            manifest.each_package_set(false) do |source|
                Autoproj.load_if_present(source, source.local_dir, "init.rb")
            end

            # Loads OS package definitions once and for all
            Autoproj.load_osdeps_from_package_sets

            # Load the required autobuild definitions
            if !silent
                Autoproj.message("autoproj: loading ...", :bold)
                if !Autoproj.reconfigure?
                    Autoproj.message("run 'autoproj reconfigure' to change configuration options", :bold)
                    Autoproj.message("and use 'autoproj switch-config' to change the remote source for", :bold)
                    Autoproj.message("autoproj's main build configuration", :bold)
                end
            end
            manifest.each_autobuild_file do |source, name|
                Autoproj.import_autobuild_file source, name
            end

            # Now, load the package's importer configurations (from the various
            # source.yml files)
            manifest.load_importers

            # Auto-add packages that are
            #  * present on disk
            #  * listed in the layout part of the manifest
            #  * but have no definition
            explicit = manifest.normalized_layout
            explicit.each do |pkg_or_set, layout_level|
                next if Autobuild::Package[pkg_or_set]
                next if manifest.has_package_set?(pkg_or_set)

                # This is not known. Check if we can auto-add it
                full_path = File.expand_path(File.join(Autoproj.root_dir, layout_level, pkg_or_set))
                next if !File.directory?(full_path)

                handler, srcdir = Autoproj.package_handler_for(full_path)
                if handler
                    Autoproj.message "  auto-adding #{pkg_or_set} #{"in #{layout_level} " if layout_level != "/"}using the #{handler.gsub(/_package/, '')} package handler"
                    Autoproj.in_package_set(manifest.local_package_set, manifest.file) do
                        send(handler, pkg_or_set)
                    end
                else
                    Autoproj.warn "cannot auto-add #{pkg_or_set}: unknown package type"
                end
            end

            # We finished loading the configuration files. Not all configuration
            # is done (since we need to process the package setup blocks), but
            # save the current state of the configuration anyway.
            Autoproj.save_config
        end

        def self.update_configuration
            manifest = Autoproj.manifest

            # Load the installation's manifest a first time, to check if we should
            # update it ... We assume that the OS dependencies for this VCS is already
            # installed (i.e. that the user did not remove it)
            if manifest.vcs
                manifest.update_yourself
                manifest_path = File.join(Autoproj.config_dir, 'manifest')
                manifest.load(manifest_path)
            end

            source_os_dependencies = manifest.each_remote_source(false).
                inject(Set.new) do |set, source|
                    set << source.vcs.type if !source.local?
                end

            # Update the remote sources if there are any
            if manifest.has_remote_sources?
                if manifest.should_update_remote_sources
                    Autoproj.message("autoproj: updating remote definitions of package sets", :bold)
                end

                # If we need to install some packages to import our remote sources, do it
                if update_os_dependencies?
                    Autoproj.osdeps.install(source_os_dependencies)
                end

                if manifest.should_update_remote_sources
                    manifest.update_remote_sources
                end
                Autoproj.message
            end
        end

        def self.setup_package_directories(pkg)
            pkg_name = pkg.name

            layout =
                if randomize_layout?
                    Digest::SHA256.hexdigest(pkg_name)[0, 12]
                else manifest.whereis(pkg_name)
                end

            place =
                if target = manifest.moved_packages[pkg_name]
                    File.join(layout, target)
                else
                    File.join(layout, pkg_name)
                end

            pkg = Autobuild::Package[pkg_name]
            pkg.srcdir = File.join(Autoproj.root_dir, place)
            pkg.prefix = File.join(Autoproj.build_dir, layout)
            pkg.doc_target_dir = File.join(Autoproj.build_dir, 'doc', pkg_name)
            pkg.logdir = File.join(pkg.prefix, "log")
        end


        def self.setup_all_package_directories
            # Override the package directories from our reused installations
            imported_packages = Set.new
            Autoproj.manifest.reused_installations.each do |manifest|
                manifest.each do |pkg|
                    imported_packages << pkg.name
                    Autobuild::Package[pkg.name].srcdir = pkg.srcdir
                    Autobuild::Package[pkg.name].prefix = pkg.prefix
                end
            end

            manifest = Autoproj.manifest
            manifest.packages.each_value do |pkg_def|
                pkg = pkg_def.autobuild
                next if imported_packages.include?(pkg_def.name)
                setup_package_directories(pkg)
            end
        end

        def self.finalize_package_setup
            # Now call the blocks that the user defined in the autobuild files. We do it
            # now so that the various package directories are properly setup
            manifest.packages.each_value do |pkg|
                pkg.user_blocks.each do |blk|
                    blk[pkg.autobuild]
                end
                pkg.setup = true
            end

            # Load the package's override files. each_source must not load the
            # source.yml file, as init.rb may define configuration options that are used
            # there
            manifest.each_source(false).to_a.each do |source|
                Autoproj.load_if_present(source, source.local_dir, "overrides.rb")
            end

            # Resolve optional dependencies
            manifest.resolve_optional_dependencies

            # And, finally, disable all ignored packages on the autobuild side
            manifest.each_ignored_package do |pkg_name|
                Autobuild::Package[pkg_name].disable
            end

            update_environment

            # We now have processed the process setup blocks. All configuration
            # should be done and we can save the configuration data.
            Autoproj.save_config
        end

        # This is a bit of a killer. It loads all available package manifests,
        # but simply warns in case of errors. The reasons for that is that the
        # only packages that should really block the current processing are the
        # ones that are selected on the command line
        def self.load_all_available_package_manifests
            # Load the manifest for packages that are already present on the
            # file system
            manifest.packages.each_value do |pkg|
                if File.directory?(pkg.autobuild.srcdir)
                    begin
                        manifest.load_package_manifest(pkg.autobuild.name)
                    rescue Interrupt
                        raise
                    rescue Exception => e
                        Autoproj.warn "cannot load package manifest for #{pkg.autobuild.name}: #{e.message}"
                    end
                end
            end
        end

        def self.update_environment
            Autoproj.manifest.reused_installations.each do |manifest|
                manifest.each do |pkg|
                    Autobuild::Package[pkg.name].update_environment
                end
            end

            # Make sure that we have the environment of all selected packages
            manifest.all_selected_packages(false).each do |pkg_name|
                Autobuild::Package[pkg_name].update_environment
            end
        end

        def self.display_configuration(manifest, package_list = nil)
            # Load the manifest for packages that are already present on the
            # file system
            manifest.packages.each_value do |pkg|
                if File.directory?(pkg.autobuild.srcdir)
                    manifest.load_package_manifest(pkg.autobuild.name)
                end
            end

            all_packages = Hash.new
            if package_list
                all_selected_packages = Set.new
                package_list.each do |name|
                    all_selected_packages << name
                    Autobuild::Package[name].all_dependencies(all_selected_packages)
                end

                package_sets = Set.new
                all_selected_packages.each do |name|
                    pkg_set = manifest.definition_source(name)
                    package_sets << pkg_set
                    all_packages[name] = [manifest.package(name).autobuild, pkg_set.name]
                end

                metapackages = Set.new
                manifest.metapackages.each_value do |metap|
                    if package_list.any? { |pkg_name| metap.include?(pkg_name) }
                        metapackages << metap
                    end
                end
            else
                package_sets = manifest.each_package_set
                package_sets.each do |pkg_set|
                    pkg_set.each_package.each do |pkg|
                        all_packages[pkg.name] = [pkg, pkg_set.name]
                    end
                end

                metapackages = manifest.metapackages.values
            end

            if package_sets.empty?
                Autoproj.message("autoproj: no package sets defined in autoproj/manifest", :bold, :red)
                return
            end

            Autoproj.message
            Autoproj.message("autoproj: package sets", :bold)
            package_sets.sort_by(&:name).each do |pkg_set|
                next if pkg_set.empty?
                if pkg_set.imported_from
                    Autoproj.message "#{pkg_set.name} (imported by #{pkg_set.imported_from.name})"
                else
                    Autoproj.message "#{pkg_set.name} (listed in manifest)"
                end
                if pkg_set.local?
                    Autoproj.message "  local set in #{pkg_set.local_dir}"
                else
                    Autoproj.message "  from:  #{pkg_set.vcs}"
                    Autoproj.message "  local: #{pkg_set.local_dir}"
                end

                imports = pkg_set.each_imported_set.to_a
                if !imports.empty?
                    Autoproj.message "  imports #{imports.size} package sets"
                    if !pkg_set.auto_imports?
                        Autoproj.message "    automatic imports are DISABLED for this set"
                    end
                    imports.each do |imported_set|
                        Autoproj.message "    #{imported_set.name}"
                    end
                end

                set_packages = pkg_set.each_package.sort_by(&:name)
                Autoproj.message "  defines: #{set_packages.map(&:name).join(", ")}"
            end

            Autoproj.message
            Autoproj.message("autoproj: metapackages", :bold)
            metapackages.sort_by(&:name).each do |metap|
                Autoproj.message "#{metap.name}"
                Autoproj.message "  includes: #{metap.packages.map(&:name).sort.join(", ")}"
            end

            packages_not_present = []

            Autoproj.message
            Autoproj.message("autoproj: packages", :bold)
            all_packages.to_a.sort_by(&:first).map(&:last).each do |pkg, pkg_set|
                if File.exists?(File.join(pkg.srcdir, "manifest.xml"))
                    manifest.load_package_manifest(pkg.name)
                    manifest.resolve_optional_dependencies
                end

                pkg_manifest = pkg.description
                vcs_def = manifest.importer_definition_for(pkg.name)
                Autoproj.message "#{pkg.name}#{": #{pkg_manifest.short_documentation}" if pkg_manifest && pkg_manifest.short_documentation}", :bold
                tags = pkg.tags.to_a
                if tags.empty?
                    Autoproj.message "   no tags"
                else
                    Autoproj.message "   tags: #{pkg.tags.to_a.sort.join(", ")}"
                end
                Autoproj.message "   defined in package set #{pkg_set}"
                if File.directory?(pkg.srcdir)
                    Autoproj.message "   checked out in #{pkg.srcdir}"
                else
                    Autoproj.message "   will be checked out in #{pkg.srcdir}"
                end
                Autoproj.message "   #{vcs_def.to_s}"

                if !File.directory?(pkg.srcdir)
                    packages_not_present << pkg.name
                    Autoproj.message "   NOT checked out yet, reported dependencies will be partial"
                end

                optdeps = pkg.optional_dependencies.to_set
                real_deps = pkg.dependencies.to_a
                actual_real_deps = real_deps.find_all { |dep_name| !optdeps.include?(dep_name) }
                if !actual_real_deps.empty?
                    Autoproj.message "   deps: #{actual_real_deps.join(", ")}"
                end

                selected_opt_deps, opt_deps = optdeps.partition { |dep_name| real_deps.include?(dep_name) }
                if !selected_opt_deps.empty?
                    Autoproj.message "   enabled opt deps: #{selected_opt_deps.join(", ")}"
                end
                if !opt_deps.empty?
                    Autoproj.message "   disabled opt deps: #{opt_deps.join(", ")}"
                end

                if !pkg.os_packages.empty?
                    Autoproj.message "   OSdeps: #{pkg.os_packages.to_a.sort.join(", ")}"
                end
            end

            if !packages_not_present.empty?
                Autoproj.message
                Autoproj.warn "the following packages are not yet checked out:"
                packages_not_present.each_slice(4) do |*packages|
                    Autoproj.warn "  #{packages.join(", ")}"
                end
                Autoproj.warn "therefore, the package list above and the listed dependencies are probably not complete"
            end
        end

        # Returns the set of packages that are actually selected based on what
        # the user gave on the command line
        def self.resolve_user_selection(selected_packages, options = Hash.new)
            manifest = Autoproj.manifest

            if selected_packages.empty?
                return manifest.default_packages
            end
            selected_packages = selected_packages.to_set

            selected_packages, nonresolved = manifest.
                expand_package_selection(selected_packages, options)

            # Try to auto-add stuff if nonresolved
            nonresolved.delete_if do |sel|
                next if !File.directory?(sel)
                while sel != '/'
                    handler, srcdir = Autoproj.package_handler_for(sel)
                    if handler
                        Autoproj.message "  auto-adding #{srcdir} using the #{handler.gsub(/_package/, '')} package handler"
                        srcdir = File.expand_path(srcdir)
                        relative_to_root = Pathname.new(srcdir).relative_path_from(Pathname.new(Autoproj.root_dir))
                        pkg = Autoproj.in_package_set(manifest.local_package_set, manifest.file) do
                            send(handler, relative_to_root.to_s)
                        end
                        setup_package_directories(pkg)
                        selected_packages.select(sel, pkg.name)
                        break(true)
                    end

                    sel = File.dirname(sel)
                end
            end

            if Autoproj.verbose
                Autoproj.message "will install #{selected_packages.packages.to_a.sort.join(", ")}"
            end
            selected_packages
        end

        def self.validate_user_selection(user_selection, resolved_selection)
            not_matched = user_selection.find_all do |pkg_name|
                !resolved_selection.has_match_for?(pkg_name)
            end
            if !not_matched.empty?
                Autoproj.message("autoproj: wrong package selection on command line, cannot find a match for #{not_matched.to_a.sort.join(", ")}", :red)
            end
        end

        def self.mark_exclusion_along_revdeps(pkg_name, revdeps, chain = [], reason = nil)
            root = !reason
            chain.unshift pkg_name
            if root
                reason = Autoproj.manifest.exclusion_reason(pkg_name)
            else
                if chain.size == 1
                    Autoproj.manifest.add_exclusion(pkg_name, "its dependency #{reason}")
                else
                    Autoproj.manifest.add_exclusion(pkg_name, "#{reason} (dependency chain: #{chain.join(">")}")
                end
            end

            return if !revdeps.has_key?(pkg_name)
            revdeps[pkg_name].each do |dep_name|
                if !Autoproj.manifest.excluded?(dep_name)
                    mark_exclusion_along_revdeps(dep_name, revdeps, chain.dup, reason)
                end
            end
        end

        def self.import_packages(selection)
            selected_packages = selection.packages.
                map do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    if !pkg
                        raise ConfigError.new, "selected package #{pkg_name} does not exist"
                    end
                    pkg
                end.to_set

            # The set of all packages that are currently selected by +selection+
            all_processed_packages = Set.new
            # The reverse dependencies for the package tree. It is discovered as
            # we go on with the import
            #
            # It only contains strong dependencies. Optional dependencies are
            # not included, as we will use this only to take into account
            # package exclusion (and that does not affect optional dependencies)
            reverse_dependencies = Hash.new { |h, k| h[k] = Set.new }

            package_queue = selected_packages.to_a.sort_by(&:name)
            while !package_queue.empty?
                pkg = package_queue.shift
                # Remove packages that have already been processed
                next if all_processed_packages.include?(pkg.name)
                all_processed_packages << pkg.name

                # If the package has no importer, the source directory must
                # be there
                if !pkg.importer && !File.directory?(pkg.srcdir)
                    raise ConfigError.new, "#{pkg.name} has no VCS, but is not checked out in #{pkg.srcdir}"
                end

                ## COMPLETELY BYPASS RAKE HERE
                # The reason is that the ordering of import/prepare between
                # packages is not important BUT the ordering of import vs.
                # prepare in one package IS important: prepare is the method
                # that takes into account dependencies.
                pkg.import
                Rake::Task["#{pkg.name}-import"].instance_variable_set(:@already_invoked, true)
                manifest.load_package_manifest(pkg.name)

                # The package setup mechanisms might have added an exclusion
                # on this package. Handle this.
                if Autoproj.manifest.excluded?(pkg.name)
                    mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                    # Run a filter now, to have errors as early as possible
                    selection.filter_excluded_and_ignored_packages(Autoproj.manifest)
                    # Delete this package from the current_packages set
                    true
                end

                Autoproj.each_post_import_block(pkg) do |block|
                    block.call(pkg)
                end
                pkg.update_environment

                # Verify that its dependencies are there, and add
                # them to the selected_packages set so that they get
                # imported as well
                new_packages = []
                pkg.dependencies.each do |dep_name|
                    reverse_dependencies[dep_name] << pkg.name
                    new_packages << Autobuild::Package[dep_name]
                end
                pkg_opt_deps, _ = pkg.partition_optional_dependencies
                pkg_opt_deps.each do |dep_name|
                    new_packages << Autobuild::Package[dep_name]
                end

                new_packages.delete_if do |pkg|
                    if Autoproj.manifest.excluded?(pkg.name)
                        mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                        true
                    elsif Autoproj.manifest.ignored?(pkg.name)
                        true
                    end
                end
                package_queue.concat(new_packages.sort_by(&:name))

                # Verify that everything is still OK with the new
                # exclusions/ignores
                selection.filter_excluded_and_ignored_packages(Autoproj.manifest)
            end

	    all_enabled_packages = Set.new
	    package_queue = selection.packages.dup
	    # Run optional dependency resolution until we have a fixed point
	    while !package_queue.empty?
		pkg_name = package_queue.shift
		next if all_enabled_packages.include?(pkg_name)
		all_enabled_packages << pkg_name

		pkg = Autobuild::Package[pkg_name]
		pkg.resolve_optional_dependencies

                pkg.prepare if !pkg.disabled?
                Rake::Task["#{pkg.name}-prepare"].instance_variable_set(:@already_invoked, true)

		package_queue.concat(pkg.dependencies)
            end

            if Autoproj.verbose
                Autoproj.message "autoproj: finished importing packages"
            end

            if Autoproj::CmdLine.list_newest?
                fields = []
                Rake::Task.tasks.each do |task|
                    if task.kind_of?(Autobuild::SourceTreeTask)
                        task.timestamp
                        fields << ["#{task.name}:", task.newest_file, task.newest_time.to_s]
                    end
                end

                field_sizes = fields.inject([0, 0, 0]) do |sizes, line|
                    3.times do |i|
                        sizes[i] = [sizes[i], line[i].length].max
                    end
                    sizes
                end
                format = "  %-#{field_sizes[0]}s %-#{field_sizes[1]}s at %-#{field_sizes[2]}s"
                fields.each do |line|
                    Autoproj.message(format % line)
                end
            end

            return all_enabled_packages
        end

        def self.build_packages(selected_packages, all_enabled_packages)
            if Autoproj::CmdLine.doc?
                Autobuild.only_doc = true
                Autoproj.message("autoproj: building and installing documentation", :bold)
            else
                Autoproj.message("autoproj: building and installing packages", :bold)
            end

            if Autoproj::CmdLine.update_os_dependencies?
                manifest.install_os_dependencies(all_enabled_packages)
            end

            if selected_packages.empty? && Autobuild.do_rebuild
                # If we don't have an explicit package selection, the handling
                # of #prepare_for_rebuild is passed to Autobuild.apply. However,
                # we want to make sure that the user really wants this
                opt = BuildOption.new("", "boolean", {:doc => 'this is going to trigger a rebuild of all packages. Is that really what you want ?'}, nil)
                if !opt.ask(false)
                    raise Interrupt
                end

            elsif !selected_packages.empty? && !force_re_build_with_depends?
                if Autobuild.do_rebuild
                    selected_packages.each do |pkg_name|
                        Autobuild::Package[pkg_name].prepare_for_rebuild
                    end
                    Autobuild.do_rebuild = false
                elsif Autobuild.do_forced_build
                    selected_packages.each do |pkg_name|
                        Autobuild::Package[pkg_name].prepare_for_forced_build
                    end
                    Autobuild.do_forced_build = false
                end
            end

            Autobuild.apply(all_enabled_packages, "autoproj-build")
        end

        def self.manifest; Autoproj.manifest end
        def self.bootstrap?; !!@bootstrap end
        def self.only_status?; !!@only_status end
        def self.only_local?; !!@only_local end
        def self.check?; !!@check end
        def self.manifest_update?; !!@manifest_update end
        def self.only_config?; !!@only_config end
        def self.randomize_layout?; !!@randomize_layout end
        def self.update_os_dependencies?
            # Check if the mode disables osdeps anyway ...
            if !@update_os_dependencies.nil? && !@update_os_dependencies
                return false
            end

            # Now look for what the user wants
            Autoproj.osdeps.osdeps_mode != 'none' || !Autoproj.osdeps.silent?
        end
        class << self
            attr_accessor :update_os_dependencies
            attr_accessor :snapshot_dir
            attr_writer :list_newest
        end
        def self.display_configuration?; !!@display_configuration end
        def self.force_re_build_with_depends?; !!@force_re_build_with_depends end
        def self.partial_build?; !!@partial_build end
        def self.mail_config; @mail_config || Hash.new end
        def self.update_packages?; @mode == "update" || @mode == "envsh" || build? end
        def self.update_envsh?; @mode == "envsh" || build? || @mode == "update" end
        def self.build?; @mode =~ /build/ end
        def self.doc?; @mode == "doc" end
        def self.snapshot?; @mode == "snapshot" end
        def self.reconfigure?; @mode == "reconfigure" end
        def self.list_unused?; @mode == "list-unused" end

        def self.show_statistics?; !!@show_statistics end
        def self.ignore_dependencies?; @ignore_dependencies end

        def self.color?; @color end

        def self.osdeps?; @mode == "osdeps" end
        def self.show_osdeps?; @mode == "osdeps" && @show_osdeps end
        def self.revshow_osdeps?; @mode == "osdeps" && @revshow_osdeps end
        def self.osdeps_forced_mode; @osdeps_forced_mode end
        def self.osdeps_filter_uptodate?
            if @mode == "osdeps"
                @osdeps_filter_uptodate
            else true
            end
        end
        def self.status_exit_code?
            @status_exit_code
        end
        def self.list_newest?; @list_newest end
        def self.parse_arguments(args, with_mode = true)
            @only_status = false
            @only_local  = false
            @show_osdeps = false
            @status_exit_code = false
            @revshow_osdeps = false
            @osdeps_filter_uptodate = true
            @osdeps_forced_mode = nil
            @check = false
            @manifest_update = false
            @display_configuration = false
            @update_os_dependencies = nil
            @force_re_build_with_depends = false
            force_re_build_with_depends = nil
            @only_config = false
            @partial_build = false
            @color = true
            Autobuild.color = true
            Autobuild.doc_errors = false
            Autobuild.do_doc = false
            Autobuild.only_doc = false
            Autobuild.do_update = nil
            do_update = nil

            mail_config = Hash.new

            # Parse the configuration options
            parser = OptionParser.new do |opts|
                opts.banner = <<-EOBANNER
autoproj mode [options]
where 'mode' is one of:

-- Build
  build:  import, build and install all packages that need it. A package or package
    set name can be given, in which case only this package and its dependencies
    will be taken into account. Example:

    autoproj build drivers/hokuyo

  fast-build: builds without updating and without considering OS dependencies
  full-build: updates packages and OS dependencies, and then builds 
  force-build: triggers all build commands, i.e. don't be lazy like in "build".
           If packages are selected on the command line, only those packages
           will be affected unless the --with-depends option is used.
  rebuild: clean and then rebuild. If packages are selected on the command line,
           only those packages will be affected unless the --with-depends option
           is used.
  doc:    generate and install documentation for packages that have some

-- Status & Update
  envsh:         update the #{ENV_FILENAME} script
  osdeps:        install the OS-provided packages
  status:        displays the state of the packages w.r.t. their source VCS
  list-config:   list all available packages
  update:        only import/update packages, do not build them
  update-config: only update the configuration
  reconfigure:   change the configuration options. Additionally, the
                 --reconfigure option can be used in other modes like
                 update or build

-- Experimental Features (USE AT YOUR OWN RISK)
  check:  compares dependencies in manifest.xml with autodetected ones
          (valid only for package types that do autodetection, like
          orogen packages)
  manifest-update: like check, but updates the manifest.xml file
          (CAREFUL: optional dependencies will get added as well!!!)
  snapshot: create a standalone autoproj configuration where all packages
            are pinned to their current version. I.e. building a snapshot
            should give you the exact same result.

-- Autoproj Configuration
  bootstrap: starts a new autoproj installation. Usage:
    autoproj bootstrap [manifest_url|source_vcs source_url opt1=value1 opt2=value2 ...]

    For example:
    autoproj bootstrap git git://gitorious.org/rock/buildconfig.git

  switch-config: change where the configuration should be taken from. Syntax:
    autoproj switch-config source_vcs source_url opt1=value1 opt2=value2 ...

    For example:
    autoproj switch-config git git://gitorious.org/rock/buildconfig.git

    In case only the options need to be changed, the source_vcs and source_url fields can be omitted:

    For example:
    autoproj switch-config branch=next

-- Additional options:
    EOBANNER
                opts.on("--reconfigure", "re-ask all configuration options (build modes only)") do
                    Autoproj.reconfigure = true
                end
                opts.on("--[no-]color", "enable or disable color in status messages (enabled by default)") do |flag|
                    @color = flag
                    Autobuild.color = flag
                end
                opts.on("--[no-]progress", "enable or disable progress display (enabled by default)") do |flag|
                    Autobuild.progress_display_enabled = flag
                end
                opts.on("--version", "displays the version and then exits") do
                    puts "autoproj v#{Autoproj::VERSION}"
                    exit(0)
                end
                opts.on("--[no-]update", "[do not] update already checked-out packages (build modes only)") do |value|
                    do_update = value
                end
                opts.on("--keep-going", "-k", "continue building even though one package has an error") do
                    Autobuild.ignore_errors = true
                end
                opts.on("--os-version", "displays the operating system as detected by autoproj") do
                    os_names, os_versions = OSDependencies.operating_system
                    if !os_names
                        puts "no information about that OS"
                    else
                        puts "name(s): #{os_names.join(", ")}"
                        puts "version(s): #{os_versions.join(", ")}"
                    end
                    exit 0
                end
                opts.on('--stats', 'displays statistics about each of the phases in the package building process') do
                    @show_statistics = true
                end
                opts.on('-p LEVEL', '--parallel=LEVEL', Integer, "override the Autobuild.parallel_build_level level") do |value|
                    Autobuild.parallel_build_level = value
                end

                opts.on("--with-depends", "apply rebuild and force-build to both packages selected on the command line and their dependencies") do
                    force_re_build_with_depends = true
                end
                opts.on("--list-newest", "for each source directory, list what is the newest file used by autoproj for dependency tracking") do
                    Autoproj::CmdLine.list_newest = true
                end
                opts.on('-n', '--no-deps', 'completely ignore dependencies') do |value|
                    @ignore_dependencies = true
                end
                opts.on("--no-osdeps", "in build and update modes, disable osdeps handling") do |value|
                    @osdeps_forced_mode = 'none'
                end
                opts.on("--rshow", "in osdeps mode, shows information for each OS package") do
                    @revshow_osdeps = true
                end
                opts.on("--show", "in osdeps mode, show a per-package listing of the OS dependencies instead of installing them") do
                    @show_osdeps = true
                end
                opts.on('--version') do
                    Autoproj.message "autoproj v#{Autoproj::VERSION}"
                    Autoproj.message "autobuild v#{Autobuild::VERSION}"
                end
                opts.on("--all", "in osdeps mode, install both OS packages and RubyGem packages, regardless of the otherwise selected mode") do
                    @osdeps_forced_mode = 'all'
                end
                opts.on("--os", "in osdeps mode, install OS packages and display information about the RubyGem packages, regardless of the otherwise selected mode") do
                    if @osdeps_forced_mode == 'ruby'
                        # Make --ruby --os behave like --all
                        @osdeps_forced_mode = 'all'
                    else
                        @osdeps_forced_mode = 'os'
                    end
                end
                opts.on('--force', 'in osdeps mode, do not filter out installed and uptodate packages') do
                    @osdeps_filter_uptodate = false
                end
                opts.on("--ruby", "in osdeps mode, install only RubyGem packages and display information about the OS packages, regardless of the otherwise selected mode") do
                    if @osdeps_forced_mode == 'os'
                        # Make --ruby --os behave like --all
                        @osdeps_forced_mode = 'all'
                    else
                        @osdeps_forced_mode = 'ruby'
                    end
                end
                opts.on("--none", "in osdeps mode, do not install any package but display information about them, regardless of the otherwise selected mode") do
                    @osdeps_forced_mode = 'none'
                end
                opts.on("--local", "for status, do not access the network") do
                    @only_local = true
                end
                opts.on('--exit-code', 'in status mode, exit with a code that reflects the status of the installation (see documentation for details)') do
                    @status_exit_code = true
                end
                opts.on('--randomize-layout', 'in build and full-build, generate a random layout') do
                    @randomize_layout = true
                    Autoproj.change_option('randomize_layout', true)
                end

                opts.on("--verbose", "verbose output") do
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = false
                end
                opts.on("--debug", "debugging output") do
                    Autoproj.verbose  = true
                    Autobuild.verbose = true
                    Rake.application.options.trace = true
                    Autobuild.debug = true
                end
                opts.on('--nice NICE', Integer, 'nice the subprocesses to the given value') do |value|
                    Autobuild.nice = value
                end
                opts.on("-h", "--help", "Show this message") do
                    puts opts
                    exit
                end
                opts.on("--mail-from EMAIL", String, "From: field of the sent mails") do |from_email|
                    mail_config[:from] = from_email
                end
                opts.on("--mail-to EMAILS", String, "comma-separated list of emails to which the reports should be sent") do |emails| 
                    mail_config[:to] ||= []
                    mail_config[:to] += emails.split(',')
                end
                opts.on("--mail-subject SUBJECT", String, "Subject: field of the sent mails") do |subject_email|
                    mail_config[:subject] = subject_email
                end
                opts.on("--mail-smtp HOSTNAME", String, " address of the mail server written as hostname[:port]") do |smtp|
                    raise "invalid SMTP specification #{smtp}" unless smtp =~ /^([^:]+)(?::(\d+))?$/
                        mail_config[:smtp] = $1
                    mail_config[:port] = Integer($2) if $2 && !$2.empty?
                end
                opts.on("--mail-only-errors", "send mail only on errors") do
                    mail_config[:only_errors] = true
                end
            end

            parser.parse!(args)
            @mail_config = mail_config

            if with_mode
                @mode = args.shift
                unknown_mode = catch(:unknown) do
                    handle_mode(@mode, args)
                    false
                end
                if unknown_mode
                    STDERR.puts "unknown mode #{@mode}"
                    STDERR.puts "run autoproj --help for more documentation"
                    exit(1)
                end
            end

            selection = args.dup
            @partial_build = !selection.empty?
            @force_re_build_with_depends = force_re_build_with_depends if !force_re_build_with_depends.nil?
            Autobuild.do_update = do_update if !do_update.nil?
            selection

        rescue OptionParser::InvalidOption => e
            raise ConfigError, e.message, e.backtrace
        end

        def self.handle_mode(mode, remaining_args)
            case mode
            when "update-sets"
                Autoproj.warn("update-sets is deprecated. Use update-config instead")
                mode = "update-config"
            when "list-sets"
                Autoproj.warn("list-sets is deprecated. Use list-config instead")
                mode = "list-config"
            end

            case mode
            when "bootstrap"
                @bootstrap = true
                bootstrap(*remaining_args)
                remaining_args.clear

                @display_configuration = false
                Autobuild.do_build  = false
                Autobuild.do_update = false
                @update_os_dependencies = false
                @only_config = true

            when "switch-config"
                if Dir.pwd.start_with?(Autoproj.remotes_dir) || Dir.pwd.start_with?(Autoproj.config_dir)
                    raise ConfigError, "you cannot run autoproj switch-config from autoproj's configuration directory or one of its subdirectories"
                end

                # We must switch to the root dir first, as it is required by the
                # configuration switch code. This is acceptable as long as we
                # quit just after the switch
                Dir.chdir(Autoproj.root_dir)
                if switch_config(*remaining_args)
                    Autobuild.do_update = true
                    Autobuild.do_build  = false
                    @update_os_dependencies = false
                    @only_config = true
                    remaining_args.clear
                else
                    exit 0
                end

            when "reconfigure"
                Autoproj.reconfigure = true
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false

            when "fast-build"
                Autobuild.do_update = false
                Autobuild.do_build  = true
                @update_os_dependencies = false
            when "build"
                Autobuild.do_update = nil
                Autobuild.do_build  = true
                @update_os_dependencies = nil
            when "force-build"
                Autobuild.do_update = nil
                Autobuild.do_build  = true
                @update_os_dependencies = nil
                Autobuild.do_forced_build = true
            when "rebuild"
                Autobuild.do_update = nil
                Autobuild.do_build  = true
                @update_os_dependencies = nil
                Autobuild.do_rebuild = true
            when "full-build"
                Autobuild.do_update = true
                Autobuild.do_build  = true
                @update_os_dependencies = true
            when "snapshot"
                @snapshot_dir = remaining_args.shift
                if !snapshot_dir
                    raise ConfigError.new, "target directory missing\nusage: autoproj snapshot target_dir"
                end
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
            when "update"
                Autobuild.do_update = true
                Autobuild.do_build  = false
                @update_os_dependencies = true
            when "check"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
                @check = true
            when "manifest-update"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
                @manifest_update = true
            when "osdeps"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = true
            when "status"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
                @only_status = true
            when "envsh"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
            when "update-config"
                Autobuild.do_update = true
                Autobuild.do_build  = false
                @update_os_dependencies = false
                @only_config = true
            when "list-config"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
                @only_config = true
                @display_configuration = true
            when "doc"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
                Autobuild.do_doc    = true
                Autobuild.only_doc  = true
            when "list-unused"
                Autobuild.do_update = false
                Autobuild.do_build  = false
                @update_os_dependencies = false
            else
                throw :unknown, true
            end
            nil
        end

        StatusResult = Struct.new :uncommitted, :local, :remote
        def self.display_status(packages)
            last_was_in_sync = false
            result = StatusResult.new

            sync_packages = ""
            packages.each do |pkg|
                lines = []

                pkg_name =
                    if pkg.respond_to?(:text_name)
                        pkg.text_name
                    else pkg.autoproj_name
                    end

                if !pkg.importer
                    lines << Autoproj.color("  is a local-only package (no VCS)", :bold, :red)
                elsif !pkg.importer.respond_to?(:status)
                    lines << Autoproj.color("  the #{pkg.importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)
                elsif !File.directory?(pkg.srcdir)
                    lines << Autoproj.color("  is not imported yet", :magenta)
                else
                    status = pkg.importer.status(pkg,@only_local)
                    if status.uncommitted_code
                        lines << Autoproj.color("  contains uncommitted modifications", :red)
                        result.uncommitted = true
                    end

                    case status.status
                    when Autobuild::Importer::Status::UP_TO_DATE
                        if !status.uncommitted_code
                            if sync_packages.size > 80
                                Autoproj.message "#{sync_packages},"
                                sync_packages = ""
                            end
                            msg = if sync_packages.empty?
                                      pkg_name
                                  else
                                      ", #{pkg_name}"
                                  end
                            STDERR.print msg
                            sync_packages = "#{sync_packages}#{msg}"
                            next
                        else
                            lines << Autoproj.color("  local and remote are in sync", :green)
                        end
                    when Autobuild::Importer::Status::ADVANCED
                        result.local = true
                        lines << Autoproj.color("  local contains #{status.local_commits.size} commit that remote does not have:", :blue)
                        status.local_commits.each do |line|
                            lines << Autoproj.color("    #{line}", :blue)
                        end
                    when Autobuild::Importer::Status::SIMPLE_UPDATE
                        result.remote = true
                        lines << Autoproj.color("  remote contains #{status.remote_commits.size} commit that local does not have:", :magenta)
                        status.remote_commits.each do |line|
                            lines << Autoproj.color("    #{line}", :magenta)
                        end
                    when Autobuild::Importer::Status::NEEDS_MERGE
                        result.local  = true
                        result.remote = true
                        lines << "  local and remote have diverged with respectively #{status.local_commits.size} and #{status.remote_commits.size} commits each"
                        lines << Autoproj.color("  -- local commits --", :blue)
                        status.local_commits.each do |line|
                            lines << Autoproj.color("   #{line}", :blue)
                        end
                        lines << Autoproj.color("  -- remote commits --", :magenta)
                        status.remote_commits.each do |line|
                            lines << Autoproj.color("   #{line}", :magenta)
                        end
                    end
                end

                if !sync_packages.empty?
                    Autoproj.message("#{sync_packages}: #{color("local and remote are in sync", :green)}")
                    sync_packages = ""
                end

                STDERR.print 

                if lines.size == 1
                    Autoproj.message "#{pkg_name}: #{lines.first}"
                else
                    Autoproj.message "#{pkg_name}:"
                    lines.each do |l|
                        Autoproj.message l
                    end
                end
            end
            if !sync_packages.empty?
                Autoproj.message("#{sync_packages}: #{color("local and remote are in sync", :green)}")
                sync_packages = ""
            end
            return result
        end

        def self.status(packages)
            console = Autoproj.console
            
            sources = Autoproj.manifest.each_configuration_source.
                map do |vcs, text_name, local_dir|
                    Autoproj::Manifest.create_autobuild_package(vcs, text_name, local_dir)
                end

            if !sources.empty?
                Autoproj.message("autoproj: displaying status of configuration", :bold)
                display_status(sources)
                STDERR.puts
            end


            Autoproj.message("autoproj: displaying status of packages", :bold)
            packages = packages.sort.map do |pkg_name|
                Autobuild::Package[pkg_name]
            end
            display_status(packages)
        end

        def self.switch_config(*args)
            Autoproj.load_config
            if Autoproj.has_config_key?('manifest_source')
                vcs = VCSDefinition.from_raw(Autoproj.user_config('manifest_source'))
            end

            if args.first =~ /^(\w+)=/
                # First argument is an option string, we are simply setting the
                # options without changing the type/url
                type, url = vcs.type, vcs.url
            else
                type, url = args.shift, args.shift
            end
            options = args

            url = VCSDefinition.to_absolute_url(url)

            if vcs && (vcs.type == type && vcs.url == url)
                # Don't need to do much: simply change the options and save the config
                # file, the VCS handler will take care of the actual switching
                vcs_def = Autoproj.user_config('manifest_source')
                options.each do |opt|
                    opt_name, opt_value = opt.split('=')
                    vcs_def[opt_name] = opt_value
                end
                # Validate the VCS definition, but save the hash as-is
                VCSDefinition.from_raw(vcs_def)
                Autoproj.change_option "manifest_source", vcs_def.dup, true
                Autoproj.save_config
                true

            else
                # We will have to delete the current autoproj directory. Ask the user.
                opt = Autoproj::BuildOption.new("delete current config", "boolean",
                            Hash[:default => "false",
                                :doc => "delete the current configuration ? (required to switch)"], nil)

                return if !opt.ask(nil)

                Dir.chdir(Autoproj.root_dir) do
                    do_switch_config(true, type, url, *options)
                end
                false
            end
        end

        def self.do_switch_config(delete_current, type, url, *options)
            vcs_def = Hash.new
            vcs_def[:type] = type
            vcs_def[:url]  = VCSDefinition.to_absolute_url(url)
            options.each do |opt|
                name, value = opt.split("=")
                if value =~ /^\d+$/
                    value = Integer(value)
                end

                vcs_def[name] = value
            end

            vcs = VCSDefinition.from_raw(vcs_def)

            # Install the OS dependencies required for this VCS
	    Autoproj::OSDependencies.define_osdeps_mode_option
            osdeps = Autoproj::OSDependencies.load_default
            osdeps.osdeps_mode
            osdeps.install([vcs.type])

            # Now check out the actual configuration
            config_dir = File.join(Dir.pwd, "autoproj")
            if delete_current
                # Find a backup name for it
                backup_base_name = backup_name = "#{config_dir}.bak"
                index = 0
                while File.directory?(backup_name)
                    backup_name = "#{backup_base_name}-#{index}.bak"
                    index += 1
                end
                    
                FileUtils.mv config_dir, backup_name
            end
            Autoproj::Manifest.update_package_set(vcs, "autoproj main configuration", config_dir)

            # If the new tree has a configuration file, load it and set
            # manifest_source
            Autoproj.load_config

            # And now save the options: note that we keep the current option set even
            # though we switched configuration. This is not a problem as undefined
            # options will not be reused
            #
            # TODO: cleanup the options to only keep the relevant ones
            vcs_def = Hash['type' => type, 'url' => url]
            options.each do |opt|
                opt_name, opt_val = opt.split '='
                vcs_def[opt_name] = opt_val
            end
            # Validate the option hash, just in case
            VCSDefinition.from_raw(vcs_def)
            # Save the new options
            Autoproj.change_option "manifest_source", vcs_def.dup, true
            Autoproj.save_config

        rescue Exception => e
            Autoproj.error "switching configuration failed: #{e.message}"
            if backup_name
                Autoproj.error "restoring old configuration"
                FileUtils.rm_rf config_dir if config_dir
                FileUtils.mv backup_name, config_dir
            end
            raise
        ensure
            if backup_name
                FileUtils.rm_rf backup_name
            end
        end

        def self.bootstrap(*args)
            if File.exists?(File.join("autoproj", "manifest"))
                raise ConfigError.new, "this installation is already bootstrapped. Remove the autoproj directory if it is not the case"
            end

            require 'set'
            curdir_entries = Dir.entries('.').to_set - [".", "..", "autoproj_bootstrap", ".gems", @env].to_set
            if !curdir_entries.empty? && ENV['AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR'] != '1'
                while true
                    print "The current directory is not empty, continue bootstrapping anyway ? [yes] "
                    STDOUT.flush
                    answer = STDIN.readline.chomp
                    if answer == "no"
                        exit
                    elsif answer == "" || answer == "yes"
                        # Set this environment variable since we might restart
                        # autoproj later on.
                        ENV['AUTOPROJ_BOOTSTRAP_IGNORE_NONEMPTY_DIR'] = '1'
                        break
                    else
                        STDOUT.puts "invalid answer. Please answer 'yes' or 'no'"
                        STDOUT.flush
                    end
                end
            end

            Autobuild.logdir = File.join(Autoproj.prefix, 'log')

            # Check if GEM_HOME is set. If it is the case, assume that we are
            # bootstrapping from another installation directory and start by
            # copying the .gems directory
            #
            # We don't use Autoproj.gem_home there as we might not be in an
            # autoproj directory at all
            gem_home = ENV['AUTOPROJ_GEM_HOME'] || File.join(Dir.pwd, ".gems")
            if ENV['GEM_HOME'] && Autoproj.in_autoproj_installation?(ENV['GEM_HOME']) &&
                ENV['GEM_HOME'] != gem_home
                if !File.exists?(gem_home)
                    Autoproj.message "autoproj: reusing bootstrap from #{File.dirname(ENV['GEM_HOME'])}"
                    FileUtils.cp_r ENV['GEM_HOME'], gem_home
                end
                ENV['GEM_HOME'] = gem_home

                Autoproj.message "restarting bootstrapping from #{Dir.pwd}"

                require 'rbconfig'
                ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                exec ruby, $0, *ARGV
            end

            # If we are not getting the installation setup from a VCS, copy the template
            # files
            if args.empty? || args.size == 1
                sample_dir = File.expand_path(File.join("..", "..", "samples"), File.dirname(__FILE__))
                FileUtils.cp_r File.join(sample_dir, "autoproj"), "autoproj"
            end

            if args.size == 1 # the user asks us to download a manifest
                manifest_url = args.first
                Autoproj.message("autoproj: downloading manifest file #{manifest_url}", :bold)
                manifest_data =
                    begin open(manifest_url) { |file| file.read }
                    rescue
                        # Delete the autoproj directory
                        FileUtils.rm_rf 'autoproj'
                        raise ConfigError.new, "cannot read #{manifest_url}, did you mean 'autoproj bootstrap VCSTYPE #{manifest_url}' ?"
                    end

                File.open(File.join(Autoproj.config_dir, "manifest"), "w") do |io|
                    io.write(manifest_data)
                end

            elsif args.size >= 2 # is a VCS definition for the manifest itself ...
                type, url, *options = *args
                url = VCSDefinition.to_absolute_url(url, Dir.pwd)
                do_switch_config(false, type, url, *options)
            end

            handle_ruby_version
            Autoproj.save_config

            Autobuild.env_set 'RUBYOPT', '-rubygems'
            Autobuild.env_set 'GEM_HOME', Autoproj.gem_home
            Autobuild.env_add_path 'PATH', File.join(Autoproj.gem_home, 'bin')
            Autobuild.env_inherit 'PATH'
            Autobuild.env_add_path 'GEM_PATH', Autoproj.gem_home
            Autobuild.env_inherit 'GEM_PATH'
            Autoproj.export_env_sh
        end

        def self.missing_dependencies(pkg)
            manifest = Autoproj.manifest.package_manifests[pkg.name]
            all_deps = pkg.dependencies.map do |dep_name|
                dep_pkg = Autobuild::Package[dep_name]
                if dep_pkg then dep_pkg.name
                else dep_name
                end
            end

            if manifest
                declared_deps = manifest.each_dependency.to_a
                missing = all_deps - declared_deps
            else
                missing = all_deps
            end

            missing.to_set.to_a.sort
        end

        # Verifies that each package's manifest is up-to-date w.r.t. the
        # automatically-detected dependencies
        #
        # Only useful for package types that do some automatic dependency
        # detection
        def self.check(packages)
            packages.sort.each do |pkg_name|
                result = []

                pkg = Autobuild::Package[pkg_name]
                manifest = Autoproj.manifest.package_manifests[pkg.name]

                # Check if the manifest contains rosdep tags
                # if manifest && !manifest.each_os_dependency.to_a.empty?
                #     result << "uses rosdep tags, convert them to normal <depend .../> tags"
                # end

                missing = missing_dependencies(pkg)
                if !missing.empty?
                    result << "missing dependency tags for: #{missing.join(", ")}"
                end

                if !result.empty?
                    Autoproj.message pkg.name
                    Autoproj.message "  #{result.join("\n  ")}"
                end
            end
        end

        def self.manifest_update(packages)
            packages.sort.each do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
                manifest = Autoproj.manifest.package_manifests[pkg.name]

                xml = 
                    if !manifest
                        Nokogiri::XML::Document.parse("<package></package>") do |c|
                            c.noblanks
                        end
                    else
                        manifest.xml.dup
                    end

                # Add missing dependencies
                missing = missing_dependencies(pkg)
                if !missing.empty?
                    package_node = xml.xpath('/package').to_a.first
                    missing.each do |pkg_name|
                        node = Nokogiri::XML::Node.new("depend", xml)
                        node['package'] = pkg_name
                        package_node.add_child(node)
                    end
                    modified = true
                end

                # Save the manifest back
                if modified
                    path = File.join(pkg.srcdir, 'manifest.xml')
                    File.open(path, 'w') do |io|
                        io.write xml.to_xml
                    end
                    if !manifest
                        Autoproj.message "created #{path}"
                    else
                        Autoproj.message "modified #{path}"
                    end
                end
            end
        end

        def self.snapshot(target_dir, packages)
            # First, copy the configuration directory to create target_dir
            if File.exists?(target_dir)
                raise ArgumentError, "#{target_dir} already exists"
            end
            FileUtils.cp_r Autoproj.config_dir, target_dir

            # Now, create snapshot information for each of the packages
            version_control = []
            packages.each do |package_name|
                package  = Autobuild::Package[package_name]
                importer = package.importer
                if !importer
                    Autoproj.message "cannot snapshot #{package_name} as it has no importer"
                    next
                elsif !importer.respond_to?(:snapshot)
                    Autoproj.message "cannot snapshot #{package_name} as the #{importer.class} importer does not support it"
                    next
                end

                vcs_info = importer.snapshot(package, target_dir)
                if vcs_info
                    version_control << Hash[package_name, vcs_info]
                end
            end

            overrides_path = File.join(target_dir, 'overrides.yml')
            if File.exists?(overrides_path)
                overrides = YAML.load(File.read(overrides_path))
            end
            # In Ruby 1.9, an empty file results in YAML.load returning false
            overrides ||= Hash.new

            if overrides['overrides']
                overrides['overrides'].concat(version_control)
            else
                overrides['overrides'] = version_control
            end

            File.open(overrides_path, 'w') do |io|
                io.write YAML.dump(overrides)
            end
        end

        # Displays the reverse OS dependencies (i.e. for each osdeps package,
        # who depends on it and where it is defined)
        def self.revshow_osdeps(packages)
            _, ospkg_to_pkg = Autoproj.manifest.list_os_dependencies(packages)

            # A mapping from a package name to
            #   [is_os_pkg, is_gem_pkg, definitions, used_by]
            #
            # where 
            #
            # +used_by+ is the set of autobuild package names that use this
            # osdeps package
            #
            # +definitions+ is a osdep_name => definition_file mapping
            mapping = Hash.new { |h, k| h[k] = Array.new }
            used_by = Hash.new { |h, k| h[k] = Array.new }
            ospkg_to_pkg.each do |pkg_osdep, pkgs|
                used_by[pkg_osdep].concat(pkgs)
                packages = Autoproj.osdeps.resolve_package(pkg_osdep)
                packages.each do |handler, status, entries|
                    entries.each do |entry|
                        if entry.respond_to?(:join)
                            entry = entry.join(", ")
                        end
                        mapping[entry] << [pkg_osdep, handler, Autoproj.osdeps.source_of(pkg_osdep)]
                    end
                end
            end

            mapping = mapping.sort_by(&:first)
            mapping.each do |pkg_name, handlers|
                puts pkg_name
                depended_upon = Array.new
                handlers.each do |osdep_name, handler, source|
                    install_state = 
                        if handler.respond_to?(:installed?)
                            !!handler.installed?(pkg_name)
                        end
                    install_state =
                        if install_state == false
                            ", currently not installed"
                        elsif install_state == true
                            ", currently installed"
                        end # nil means "don't know"

                    puts "  defined as #{osdep_name} (#{handler.name}) in #{source}#{install_state}"
                    depended_upon.concat(used_by[osdep_name])
                end
                puts "  depended-upon by #{depended_upon.sort.join(", ")}"
            end
        end

        # Displays the OS dependencies required by the given packages
        def self.show_osdeps(packages)
            _, ospkg_to_pkg = Autoproj.manifest.list_os_dependencies(packages)

            # ospkg_to_pkg is the reverse mapping to what we want. Invert it
            mapping = Hash.new { |h, k| h[k] = Set.new }
            ospkg_to_pkg.each do |ospkg, pkgs|
                pkgs.each do |pkg_name|
                    mapping[pkg_name] << ospkg
                end
            end
        
            # Now sort it by package name (better for display)
            package_osdeps = mapping.to_a.
                sort_by { |name, _| name }

            package_osdeps.each do |pkg_name, pkg_osdeps|
                if pkg_osdeps.empty?
                    puts "  #{pkg_name}: no OS dependencies"
                    next
                end

                packages = Autoproj.osdeps.resolve_os_dependencies(pkg_osdeps)
                puts pkg_name
                packages.each do |handler, packages|
                    puts "  #{handler.name}: #{packages.sort.join(", ")}"
                    needs_update = handler.filter_uptodate_packages(packages)
                    if needs_update.to_set != packages.to_set
                        if needs_update.empty?
                            puts "    all packages are up to date"
                        else
                            puts "    needs updating: #{needs_update.sort.join(", ")}"
                        end
                    end
                end
            end
        end

        # This method sets up autoproj and loads the configuration available in
        # the current autoproj installation. It is meant as a simple way to
        # initialize an autoproj environment for standalone tools
        #
        # Beware, it changes the current directory to the autoproj root dir
        def self.initialize_and_load(cmdline_arguments = ARGV.dup)
            require 'autoproj/autobuild'
            require 'open-uri'
            require 'autoproj/cmdline'

            remaining_arguments = Autoproj::CmdLine.
                parse_arguments(cmdline_arguments, false)
            Dir.chdir(Autoproj.root_dir)

            Autoproj::CmdLine.update_os_dependencies = false
            Autoproj::CmdLine.initialize
            Autoproj::CmdLine.update_configuration
            Autoproj::CmdLine.load_configuration
            Autoproj::CmdLine.setup_all_package_directories
            Autoproj::CmdLine.finalize_package_setup

            load_all_available_package_manifests
            update_environment
            remaining_arguments
        end

        def self.initialize_root_directory
            Autoproj.root_dir
        rescue Autoproj::UserError => error
            if ENV['GEM_HOME']
                Dir.chdir(File.join(ENV['GEM_HOME'], '..'))
                begin Autoproj.root_dir
                rescue Autoproj::UserError
                    raise error
                end
            else
                raise
            end
        end

        def self.list_unused(all_enabled_packages)
            all_enabled_packages = all_enabled_packages.map do |pkg_name|
                Autobuild::Package[pkg_name]
            end
            leaf_dirs = (all_enabled_packages.map(&:srcdir) +
                all_enabled_packages.map(&:prefix)).to_set
            leaf_dirs << Autoproj.config_dir
            leaf_dirs << Autoproj.gem_home
            leaf_dirs << Autoproj.remotes_dir

            root = Autoproj.root_dir
            all_dirs = leaf_dirs.dup
            leaf_dirs.each do |dir|
                dir = File.dirname(dir)
                while dir != root
                    break if all_dirs.include?(dir)
                    all_dirs << dir
                    dir = File.dirname(dir)
                end
            end
            all_dirs << Autoproj.root_dir

            unused = Set.new
            Find.find(Autoproj.root_dir) do |path|
                next if !File.directory?(path)
                if !all_dirs.include?(path)
                    unused << path
                    Find.prune
                elsif leaf_dirs.include?(path)
                    Find.prune
                end
            end


            root = Pathname.new(Autoproj.root_dir)
            Autoproj.message
            Autoproj.message "The following directories are not part of a package used in the current autoproj installation", :bold
            unused.to_a.sort.each do |dir|
                puts "  #{Pathname.new(dir).relative_path_from(root)}"
            end
        end

        def self.export_installation_manifest
            File.open(File.join(Autoproj.root_dir, ".autoproj-installation-manifest"), 'w') do |io|
                Autoproj.manifest.all_selected_packages.each do |pkg_name|
                    pkg = Autobuild::Package[pkg_name]
                    io.puts "#{pkg_name},#{pkg.srcdir},#{pkg.prefix}"
                end
            end
        end

        def self.report
            Autobuild::Reporting.report do
                yield
            end
            Autobuild::Reporting.success

        rescue ConfigError => e
            STDERR.puts
            STDERR.puts color(e.message, :red, :bold)
            if Autoproj.in_autoproj_installation?(Dir.pwd)
                root_dir = /^#{Regexp.quote(Autoproj.root_dir)}(?!\/\.gems)/
                e.backtrace.find_all { |path| path =~ root_dir }.
                    each do |path|
                        STDERR.puts color("  in #{path}", :red, :bold)
                    end
            end
            if Autobuild.debug then raise
            else exit 1
            end
        rescue Interrupt
            STDERR.puts
            STDERR.puts color("Interrupted by user", :red, :bold)
            if Autobuild.debug then raise
            else exit 1
            end
        end
    end
end

