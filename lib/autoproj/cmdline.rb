require 'highline'
require 'utilrb/module/attr_predicate'
require 'autoproj/ops/build'
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
    def self.warn(message, *style)
        Autobuild.warn(message, *style)
    end

    module CmdLine
        def self.config
            Autoproj.config
        end

        def self.ruby_executable
            Autoproj.config.ruby_executable
        end

        def self.install_ruby_shims
            install_suffix = ""
            if match = /ruby(.*)$/.match(RbConfig::CONFIG['RUBY_INSTALL_NAME'])
                install_suffix = match[1]
            end

            bindir = File.join(Autoproj.build_dir, 'bin')
            FileUtils.mkdir_p bindir
            Autoproj.env_add 'PATH', bindir

            File.open(File.join(bindir, 'ruby'), 'w') do |io|
                io.puts "#! /bin/sh"
                io.puts "exec #{ruby_executable} \"$@\""
            end
            FileUtils.chmod 0755, File.join(bindir, 'ruby')

            ['gem', 'irb', 'testrb'].each do |name|
                # Look for the corresponding gem program
                prg_name = "#{name}#{install_suffix}"
                if File.file?(prg_path = File.join(RbConfig::CONFIG['bindir'], prg_name))
                    File.open(File.join(bindir, name), 'w') do |io|
                        io.puts "#! #{ruby_executable}"
                        io.puts "exec \"#{prg_path}\", *ARGV"
                    end
                    FileUtils.chmod 0755, File.join(bindir, name)
                end
            end
        end

        def self.validate_current_root
            # Make sure that the currently loaded env.sh is actually us
            if ENV['AUTOPROJ_CURRENT_ROOT'] && !ENV['AUTOPROJ_CURRENT_ROOT'].empty? && (ENV['AUTOPROJ_CURRENT_ROOT'] != Autoproj.root_dir)
                raise ConfigError.new, "the current environment is for #{ENV['AUTOPROJ_CURRENT_ROOT']}, but you are in #{Autoproj.root_dir}, make sure you are loading the right #{ENV_FILENAME} script !"
            end
        end

        def self.initialize
            Encoding.default_internal = Encoding::UTF_8
            Encoding.default_external = Encoding::UTF_8

            Autobuild::Reporting << Autoproj::Reporter.new
            if mail_config[:to]
                Autobuild::Reporting << Autobuild::MailReporter.new(mail_config)
            end

            validate_current_root

            # Remove from LOADED_FEATURES everything that is coming from our
            # configuration directory
            Autobuild::Package.clear
            Autoproj.loaded_autobuild_files.clear
            Autoproj.load_config

            config.validate_ruby_executable
            install_ruby_shims

            config.apply_autobuild_configuration
            config.apply_autoproj_prefix

            manifest = Manifest.new
            Autoproj.manifest = manifest
            Autoproj.prepare_environment
            Autobuild.prefix  = Autoproj.build_dir
            Autobuild.srcdir  = Autoproj.root_dir
            Autobuild.logdir = File.join(Autobuild.prefix, 'log')

            Ops::Tools.load_autoprojrc

            config.each_reused_autoproj_installation do |p|
                manifest.reuse(p)
            end

            # We load the local init.rb first so that the manifest loading
            # process can use options defined there for the autoproj version
            # control information (for instance)
            Ops::Tools.load_main_initrb(manifest)

            manifest_path = File.join(Autoproj.config_dir, 'manifest')
            manifest.load(manifest_path)

            # Initialize the Autoproj.osdeps object by loading the default. The
            # rest is loaded later
            manifest.osdeps.load_default
            manifest.osdeps.silent = !osdeps?
            manifest.osdeps.filter_uptodate_packages = osdeps_filter_uptodate?
            if osdeps_forced_mode
                manifest.osdeps.osdeps_mode = osdeps_forced_mode
            end

            # Define the option NOW, as update_os_dependencies? needs to know in
            # what mode we are.
            #
            # It might lead to having multiple operating system detections, but
            # that's the best I can do for now.
	    Autoproj::OSDependencies.define_osdeps_mode_option
            manifest.osdeps.osdeps_mode

            # Do that AFTER we have properly setup Autoproj.osdeps as to avoid
            # unnecessarily redetecting the operating system
            if update_os_dependencies? || osdeps?
                Autoproj.change_option('operating_system', Autoproj::OSDependencies.operating_system(:force => true), true)
            end
        end

        def self.load_autoprojrc
            Ops::Tools.load_autoprojrc
        end

        def self.update_myself(options = Hash.new)
            options = Kernel.validate_options options,
                force: false, restart_on_update: true
            return if !options[:force] && !Autoproj::CmdLine.update_os_dependencies?

            Autoproj.config.validate_ruby_executable

            # This is a guard to avoid infinite recursion in case the user is
            # running autoproj osdeps --force
            if ENV['AUTOPROJ_RESTARTING'] == '1'
                return
            end

            did_update =
                begin
                    saved_flag = PackageManagers::GemManager.with_prerelease
                    PackageManagers::GemManager.with_prerelease = Autoproj.config.use_prerelease?
                    OSDependencies.load_default.install(%w{autobuild autoproj})
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
                Autoproj.save_config
                ENV['AUTOPROJ_RESTARTING'] = '1'
                require 'rbconfig'
                if defined?(ORIGINAL_ARGV)
                    exec(ruby_executable, $0, *ORIGINAL_ARGV)
                else
                    exec(ruby_executable, $0, *ARGV)
                end
            end
        end

        def self.load_configuration(silent = false)
            manifest = Autoproj.manifest

            manifest.each_package_set do |pkg_set|
                if Gem::Version.new(pkg_set.required_autoproj_version) > Gem::Version.new(Autoproj::VERSION)
                    raise ConfigError.new(pkg_set.source_file), "the #{pkg_set.name} package set requires autoproj v#{pkg_set.required_autoproj_version} but this is v#{Autoproj::VERSION}"
                end
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

            manifest.each_autobuild_package do |pkg|
                Autobuild.each_utility do |uname, _|
                    pkg.utility(uname).enabled =
                        config.utility_enabled_for?(uname, pkg.name)
                end
            end

            # We finished loading the configuration files. Not all configuration
            # is done (since we need to process the package setup blocks), but
            # save the current state of the configuration anyway.
            Autoproj.save_config
        end

        def self.update_configuration
            Ops::Configuration.new(Autoproj.manifest, Ops.loader).update_configuration(only_local?)
        end

        def self.setup_package_directories(pkg)
            pkg_name = pkg.name

            layout =
                if config.randomize_layout?
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
            manifest = Autoproj.manifest

            # Override the package directories from our reused installations
            imported_packages = Set.new
            Autoproj.manifest.reused_installations.each do |imported_manifest|
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

        def self.finalize_package_setup
            # Now call the blocks that the user defined in the autobuild files. We do it
            # now so that the various package directories are properly setup
            manifest.packages.each_value do |pkg|
                pkg.user_blocks.each do |blk|
                    blk[pkg.autobuild]
                end
                pkg.setup = true
            end

            manifest.each_package_set do |source|
                Autoproj.load_if_present(source, source.local_dir, "overrides.rb")
            end

            # Resolve optional dependencies
            manifest.resolve_optional_dependencies

            # And, finally, disable all ignored packages on the autobuild side
            manifest.each_ignored_package do |pkg_name|
                pkg = Autobuild::Package[pkg_name]
                if !pkg
                    Autoproj.warn "ignore line #{pkg_name} does not match anything"
                else
                    pkg.disable
                end
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
                    pkg_set = manifest.definition_package_set(name)
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
                    Autoproj.message "#{pkg_set.name} (imported by #{pkg_set.imported_from.map(&:name).join(", ")})"
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
                raise ConfigError.new, "autoproj: wrong package selection on command line, cannot find a match for #{not_matched.to_a.sort.join(", ")}"
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
                    Autoproj.manifest.add_exclusion(pkg_name, "#{reason} (dependency chain: #{chain.join(">")})")
                end
            end

            return if !revdeps.has_key?(pkg_name)
            revdeps[pkg_name].each do |dep_name|
                if !Autoproj.manifest.excluded?(dep_name)
                    mark_exclusion_along_revdeps(dep_name, revdeps, chain.dup, reason)
                end
            end
        end

        def self.import_packages(selection, options = Hash.new)
            options = Kernel.validate_options options,
                warn_about_ignored_packages: true,
                warn_about_excluded_packages: true

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
                pkg.import(only_local?)
                Rake::Task["#{pkg.name}-import"].instance_variable_set(:@already_invoked, true)
                manifest.load_package_manifest(pkg.name)

                # The package setup mechanisms might have added an exclusion
                # on this package. Handle this.
                if Autoproj.manifest.excluded?(pkg.name)
                    mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                    # Run a filter now, to have errors as early as possible
                    selection.filter_excluded_and_ignored_packages(Autoproj.manifest)
                    # Delete this package from the current_packages set
                    next
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

            if options[:warn_about_excluded_packages]
                selection.exclusions.each do |sel, pkg_names|
                    pkg_names.sort.each do |pkg_name|
                        Autoproj.warn "#{pkg_name}, which was selected for #{sel}, cannot be built: #{Autoproj.manifest.exclusion_reason(pkg_name)}", :bold
                    end
                end
            end
            if options[:warn_about_ignored_packages]
                selection.ignores.each do |sel, pkg_names|
                    pkg_names.sort.each do |pkg_name|
                        Autoproj.warn "#{pkg_name}, which was selected for #{sel}, is ignored", :bold
                    end
                end
            end

            return all_enabled_packages
        end

        def self.build_packages(selected_packages, all_enabled_packages, phases = [])
            if Autoproj::CmdLine.update_os_dependencies?
                manifest.install_os_dependencies(all_enabled_packages)
            end

            ops = Ops::Build.new(manifest, update_os_dependencies?)
            if Autobuild.do_rebuild || Autobuild.do_forced_build
                packages_to_rebuild =
                    if force_re_build_with_depends? || selected_packages.empty?
                        all_enabled_packages
                    else selected_packages
                    end

                if selected_packages.empty?
                    # If we don't have an explicit package selection, we want to
                    # make sure that the user really wants this
                    mode_name = if Autobuild.do_rebuild then 'rebuild'
                                else 'force-build'
                                end
                    opt = BuildOption.new("", "boolean", {:doc => "this is going to trigger a #{mode_name} of all packages. Is that really what you want ?"}, nil)
                    if !opt.ask(false)
                        raise Interrupt
                    end
                    if Autobuild.do_rebuild
                        ops.rebuild_all
                    else
                        ops.force_build_all
                    end
                elsif Autobuild.do_rebuild
                    ops.rebuild_packages(packages_to_rebuild, all_enabled_packages)
                else
                    ops.force_build_packages(packages_to_rebuild, all_enabled_packages)
                end
                return
            end

            if phases.include?('build')
                ops.build_packages(all_enabled_packages)
            end
            Autobuild.apply(all_enabled_packages, "autoproj-build", phases - ['build'])
        end

        def self.manifest; Autoproj.manifest end
        def self.only_status?; !!@only_status end
        def self.only_local?; !!@only_local end
        def self.check?; !!@check end
        def self.manifest_update?; !!@manifest_update end
        def self.only_config?; !!@only_config end
        def self.randomize_layout?; config.randomize_layout? end
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
        def self.color=(flag); @color = flag end

        class << self
            attr_accessor :update_from
        end
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
        def self.parse_arguments(args, with_mode = true, &additional_options)
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
            @color = true
            Autobuild.color = true
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
                opts.on('--from PATH', 'in update mode, use this existing autoproj installation to check out the packages (for importers that support this)') do |path|
                    self.update_from = Autoproj::InstallationManifest.from_root(File.expand_path(path))
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
                    config.randomize_layout = true
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
                Ops::Tools.common_options(opts)
                opts.instance_eval(&additional_options) if block_given?
            end

            args = parser.parse(args)
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
            result = StatusResult.new

            sync_packages = ""
            packages.each do |pkg|
                lines = []

                pkg_name = pkg.autoproj_name

                if !pkg.importer
                    lines << Autoproj.color("  is a local-only package (no VCS)", :bold, :red)
                elsif !pkg.importer.respond_to?(:status)
                    lines << Autoproj.color("  the #{pkg.importer.class.name.gsub(/.*::/, '')} importer does not support status display", :bold, :red)
                elsif !File.directory?(pkg.srcdir)
                    lines << Autoproj.color("  is not imported yet", :magenta)
                else
                    status = begin pkg.importer.status(pkg, only_local?)
                             rescue Interrupt
                                 raise
                             rescue Exception
                                 lines << Autoproj.color("  failed to fetch status information", :red)
                                 nil
                             end

                    if status
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
            pkg_sets = Autoproj.manifest.each_package_set.map(&:create_autobuild_package)
            if !pkg_sets.empty?
                Autoproj.message("autoproj: displaying status of configuration", :bold)
                display_status(pkg_sets)
                STDERR.puts
            end

            Autoproj.message("autoproj: displaying status of packages", :bold)
            packages = packages.sort.map do |pkg_name|
                Autobuild::Package[pkg_name]
            end
            display_status(packages)
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

        def self.versions(manifest, packages, target_dir = nil)
            # Pin package sets
            package_sets = Array.new
            manifest.each_package_set do |pkg_set|
                next if pkg_set.name == 'local'
                if pkg_set.local?
                    package_sets << Pathname.new(pkg_set.local_dir).
                        relative_path_from(Pathname.new(manifest.file).dirname).
                        to_s
                else
                    vcs_info = pkg_set.vcs.to_hash
                    if pin_info = pkg_set.snapshot(target_dir)
                        vcs_info = vcs_info.merge(pin_info)
                    end
                    package_sets << vcs_info
                end
            end
            pp package_sets

            # Now, create snapshot information for each of the packages
            version_control_info = []
            overrides_info = []
            packages.each do |package_name|
                package  = manifest.packages[package_name]
                if !package
                    raise ArgumentError, "#{package_name} is not a known package"
                end
                package_set = package.package_set
                importer = package.autobuild.importer
                if !importer
                    Autoproj.message "cannot snapshot #{package_name} as it has no importer"
                    next
                elsif !importer.respond_to?(:snapshot)
                    Autoproj.message "cannot snapshot #{package_name} as the #{importer.class} importer does not support it"
                    next
                end

                vcs_info = importer.snapshot(package.autobuild, target_dir)
                if vcs_info
                    if package_set.name == 'local'
                        version_control_info << Hash[package_name, vcs_info]
                    else
                        overrides_info << Hash[package_name, vcs_info]
                    end
                end
            end

            # combine package_set and pkg information
            overrides = Hash.new
            (overrides['version_control'] ||= Array.new).
                concat(version_control_info)
            (overrides['overrides'] ||= Array.new).
                concat(overrides_info)

            overrides
        end

        def snapshot(manifest, packages, target_dir)
            # get the versions information first and snapshot individual 
            # packages
            overrides = versions( manifest, packages, target_dir )

            # First, copy the configuration directory to create target_dir
            if File.exists?(target_dir)
                raise ArgumentError, "#{target_dir} already exists"
            end
            FileUtils.cp_r Autoproj.config_dir, target_dir
            # Finally, remove the remotes/ directory from the generated
            # buildconf, it is obsolete now
            FileUtils.rm_rf File.join(target_dir, 'remotes')

            # write manifest file
            manifest_path = File.join(target_dir, 'manifest')
            manifest_data['package_sets'] = package_sets
            File.open(manifest_path, 'w') do |io|
                YAML.dump(manifest_data, io)
            end

            # write overrides file
            overrides_path = File.join(target_dir, 'overrides.yml')
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
            if ENV['AUTOPROJ_CURRENT_ROOT']
                Dir.chdir(ENV['AUTOPROJ_CURRENT_ROOT'])
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

        def self.report(options = Hash.new)
            options = Kernel.validate_options options,
                report_success: true

            Autobuild::Reporting.report do
                yield
            end
            if options[:report_success]
                Autobuild::Reporting.success
            end

        rescue ConfigError => e
            STDERR.puts
            STDERR.puts Autoproj.color(e.message, :red, :bold)
            if Autoproj.in_autoproj_installation?(Dir.pwd)
                root_dir = /#{Regexp.quote(Autoproj.root_dir)}(?!\/\.gems)/
                e.backtrace.find_all { |path| path =~ root_dir }.
                    each do |path|
                        STDERR.puts Autoproj.color("  in #{path}", :red, :bold)
                    end
            end
            if Autobuild.debug then raise
            else exit 1
            end
        rescue Interrupt
            STDERR.puts
            STDERR.puts Autoproj.color("Interrupted by user", :red, :bold)
            if Autobuild.debug then raise
            else exit 1
            end
        end
    end
end

