module Autoproj
    module Ops
        class Import
            attr_reader :ws

            # Whether packages are added to exclusions if they error during the
            # import process
            #
            # This is mostly meant for CI operations
            def auto_exclude?
                @auto_exclude
            end
            attr_writer :auto_exclude

            def initialize(ws)
                @ws = ws
                @auto_exclude = false
            end

            def mark_exclusion_along_revdeps(pkg_name, revdeps, chain = [], reason = nil)
                root = !reason
                chain.unshift pkg_name
                if root
                    reason = ws.manifest.exclusion_reason(pkg_name)
                else
                    if chain.size == 1
                        ws.manifest.exclude_package(pkg_name, "its dependency #{reason}")
                    else
                        ws.manifest.exclude_package(pkg_name, "#{reason} (dependency chain: #{chain.join(">")})")
                    end
                end

                return if !revdeps.has_key?(pkg_name)
                revdeps[pkg_name].each do |dep_name|
                    if !ws.manifest.excluded?(dep_name)
                        mark_exclusion_along_revdeps(dep_name, revdeps, chain.dup, reason)
                    end
                end
            end

            VALID_OSDEP_AVAILABILITY =
                [OSPackageResolver::AVAILABLE, OSPackageResolver::IGNORE]

            def import_next_step(pkg, reverse_dependencies)
                new_packages = []
                pkg.dependencies.each do |dep_name|
                    reverse_dependencies[dep_name] << pkg.name
                    new_packages << ws.manifest.find_package_definition(dep_name)
                end
                pkg_opt_deps, pkg_opt_os_deps = pkg.partition_optional_dependencies
                pkg_opt_deps.each do |dep_name|
                    new_packages << ws.manifest.find_package_definition(dep_name)
                end

                # Handle OS dependencies, excluding the package if some
                # dependencies are not available
                pkg.os_packages.each do |dep_name|
                    reverse_dependencies[dep_name] << pkg.name
                end
                (pkg.os_packages | pkg_opt_os_deps).each do |dep_name|
                    if ws.manifest.excluded?(dep_name)
                        mark_exclusion_along_revdeps(dep_name, reverse_dependencies)
                    end
                end

                new_packages.delete_if do |new_pkg|
                    if ws.manifest.excluded?(new_pkg.name)
                        mark_exclusion_along_revdeps(new_pkg.name, reverse_dependencies)
                        true
                    elsif ws.manifest.ignored?(new_pkg.name)
                        true
                    end
                end
                new_packages
            end

            def pre_package_import(selection, manifest, pkg, reverse_dependencies)
                # Try to auto-exclude the package early. If the autobuild file
                # contained some information that allows us to exclude it now,
                # then let's just do it
                import_next_step(pkg, reverse_dependencies)
                if manifest.excluded?(pkg.name)
                    selection.filter_excluded_and_ignored_packages(manifest)
                    false
                elsif manifest.ignored?(pkg.name)
                    false
                elsif !pkg.importer && !File.directory?(pkg.srcdir)
                    raise ConfigError.new, "#{pkg.name} has no VCS, but is not checked out in #{pkg.srcdir}"
                else
                    true
                end
            end

            def post_package_import(selection, manifest, pkg, reverse_dependencies, auto_exclude: auto_exclude?)
                Rake::Task["#{pkg.name}-import"].instance_variable_set(:@already_invoked, true)
                if pkg.checked_out?
                    begin
                        manifest.load_package_manifest(pkg.name)
                    rescue Exception => e
                        raise if !auto_exclude
                        manifest.add_exclusion(pkg.name, "#{pkg.name} failed to import with #{e} and auto_exclude was true")
                    end
                end

                # The package setup mechanisms might have added an exclusion
                # on this package. Handle this.
                if manifest.excluded?(pkg.name)
                    mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                    # Run a filter now, to have errors as early as possible
                    selection.filter_excluded_and_ignored_packages(manifest)
                    # Delete this package from the current_packages set
                    false
                elsif manifest.ignored?(pkg.name)
                    false
                else
                    if pkg.checked_out?
                        process_post_import_blocks(pkg)
                    end
                    import_next_step(pkg, reverse_dependencies)
                end
            end

            # Install the VCS osdep for the given packages
            #
            # @param [Hash] osdeps_options the options that will be passed to
            #   {Workspace#install_os_packages}
            # @return [Set] the set of installed OS packages
            def install_vcs_packages_for(*packages, **osdeps_options)
                vcs_to_install = packages.map { |pkg| pkg.vcs.type }.uniq
                # This assumes that the VCS packages do not depend on a
                # 'strict' package mangers such as e.g. BundlerManager
                ws.install_os_packages(vcs_to_install, all: nil, **osdeps_options)
                vcs_to_install
            end

            # Install the internal dependencies for the given packages
            #
            # @param [Hash] osdeps_options the options that will be passed to
            #   {Workspace#install_os_packages}
            # @return [Set] the set of installed OS packages
            def install_internal_dependencies_for(*packages, **osdeps_options)
                packages_to_install = packages.map do |pkg|
                    pkg.autobuild.internal_dependencies
                end.flatten.uniq
                return if packages_to_install.empty?

                # This assumes that the internal dependencies do not depend on a
                # 'strict' package mangers such as e.g. BundlerManager and that
                # the package manager itself does not have any dependencies
                ws.install_os_packages(packages_to_install, all: nil, **osdeps_options)
                packages_to_install
            end

            # @api private
            #
            # Queue the work necessary to import the given package, making sure
            # that the execution results end up in a given queue
            #
            # @param executor the future executor
            # @param [Queue] completion_queue the queue where the completion
            #   results should be pushed, as a (package, time, result,
            #   error_reason) tuple
            # @param [Integer] retry_count the number of retries that are
            #   allowed. Set to zero for no retry
            # @param [Hash] import_options options passed to {Autobuild::Importer#import}
            def queue_import_work(executor, completion_queue, pkg, retry_count: nil, **import_options)
                import_future = Concurrent::Future.new(executor: executor, args: [pkg]) do |import_pkg|
                    ## COMPLETELY BYPASS RAKE HERE
                    # The reason is that the ordering of import/prepare between
                    # packages is not important BUT the ordering of import vs.
                    # prepare in one package IS important: prepare is the method
                    # that takes into account dependencies.
                    if retry_count
                        import_pkg.autobuild.importer.retry_count = retry_count
                    end
                    import_pkg.autobuild.import(**import_options)
                end
                import_future.add_observer do |time, result, reason|
                    completion_queue << [pkg, time, result, reason]
                end
                import_future.execute
            end

            # Import all packages from the given selection, and their
            # dependencies
            def import_selected_packages(selection,
                                         parallel: ws.config.parallel_import_level,
                                         recursive: true,
                                         retry_count: nil,
                                         keep_going: false,
                                         install_vcs_packages: Hash.new,
                                         non_imported_packages: :checkout,
                                         auto_exclude: auto_exclude?,
                                         **import_options)

                if ![:checkout, :ignore, :return].include?(non_imported_packages)
                    raise ArgumentError, "invalid value for 'non_imported_packages'. Expected one of :checkout, :ignore or :return but got #{non_imported_packages}"
                end

                # This is used in the ensure block, initialize as early as
                # possible
                executor = Concurrent::FixedThreadPool.new(parallel)
                manifest = ws.manifest

                selected_packages = selection.each_source_package_name.map do |pkg_name|
                    manifest.find_package_definition(pkg_name)
                end.to_set

                # The reverse dependencies for the package tree. It is discovered as
                # we go on with the import
                #
                # It only contains strong dependencies. Optional dependencies are
                # not included, as we will use this only to take into account
                # package exclusion (and that does not affect optional dependencies)
                reverse_dependencies = Hash.new { |h, k| h[k] = Set.new }

                completion_queue = Queue.new
                pending_packages = Set.new
                # The set of all packages that are currently selected by +selection+
                all_processed_packages = Set.new
                main_thread_imports = Array.new
                package_queue = selected_packages.to_a.sort_by(&:name)
                failures = Array.new
                missing_vcs = Array.new
                installed_vcs_packages = Set['none', 'local']
                while failures.empty? || keep_going
                    # Queue work for all packages in the queue
                    package_queue.each do |pkg|
                        # Remove packages that have already been processed
                        next if all_processed_packages.include?(pkg)
                        if (non_imported_packages != :checkout) && !File.directory?(pkg.autobuild.srcdir)
                            if non_imported_packages == :return
                                all_processed_packages << pkg
                                completion_queue << [pkg, Time.now, false, nil]
                                next
                            else
                                all_processed_packages << pkg
                                ws.manifest.ignore_package(pkg.name)
                                next
                            end
                        elsif install_vcs_packages && !installed_vcs_packages.include?(pkg.vcs.type)
                            missing_vcs << pkg
                            next
                        end
                        all_processed_packages << pkg

                        importer = pkg.autobuild.importer
                        if !pre_package_import(selection, manifest, pkg.autobuild, reverse_dependencies)
                            next
                        elsif !importer
                            # The validity of this is checked in
                            # pre_package_import
                            completion_queue << [pkg, Time.now, false, nil]
                            next
                        elsif importer.interactive?
                            main_thread_imports << pkg
                            next
                        elsif pkg.autobuild.checked_out? && import_options[:checkout_only]
                            main_thread_imports << pkg
                            next
                        end

                        pending_packages << pkg
                        begin
                            queue_import_work(
                                executor, completion_queue, pkg, retry_count: retry_count,
                                **import_options.merge(allow_interactive: false))
                        rescue Exception
                            pending_packages.delete(pkg)
                            raise
                        end
                        true
                    end
                    package_queue.clear

                    if completion_queue.empty? && pending_packages.empty?
                        if !missing_vcs.empty?
                            installed_vcs_packages.merge(
                                install_vcs_packages_for(*missing_vcs, **install_vcs_packages))
                            package_queue.concat(missing_vcs)
                            missing_vcs.clear
                            next
                        end

                        # We've nothing to process anymore ... process
                        # interactive imports if there are some. Otherwise,
                        # we're done
                        if main_thread_imports.empty?
                            break
                        else
                            main_thread_imports.delete_if do |pkg|
                                begin
                                    if retry_count
                                        pkg.autobuild.importer.retry_count = retry_count
                                    end
                                    result = pkg.autobuild.import(
                                        **import_options.merge(allow_interactive: true))
                                rescue Exception => reason
                                end
                                completion_queue << [pkg, Time.now, result, reason]
                            end
                        end
                    end

                    # And wait for one to finish
                    pkg, _time, _result, reason = completion_queue.pop
                    pending_packages.delete(pkg)
                    if reason
                        if reason.kind_of?(Autobuild::InteractionRequired)
                            main_thread_imports << pkg
                        elsif auto_exclude
                            manifest.add_exclusion(pkg.name, "#{pkg.name} failed to import with #{reason} and auto_exclude was true")
                            selection.filter_excluded_and_ignored_packages(manifest)
                        else
                            # One importer failed... terminate
                            Autoproj.error "import of #{pkg.name} failed"
                            if !reason.kind_of?(Interrupt)
                                Autoproj.error "#{reason}"
                            end
                            failures << reason
                        end
                    else
                        if new_packages = post_package_import(
                                selection, manifest, pkg.autobuild, reverse_dependencies,
                                auto_exclude: auto_exclude)
                            # Excluded dependencies might have caused the package to be
                            # excluded as well ... do not add any dependency to the
                            # processing queue if it is the case
                            if manifest.excluded?(pkg.name)
                                selection.filter_excluded_and_ignored_packages(manifest)
                            elsif recursive
                                package_queue = new_packages.sort_by(&:name)
                            end
                        end
                    end
                end

                all_processed_packages.delete_if do |processed_pkg|
                    ws.manifest.excluded?(processed_pkg.name) || ws.manifest.ignored?(processed_pkg.name)
                end
                return all_processed_packages, failures

            ensure
                if failures && !failures.empty? && !keep_going
                    Autoproj.error "waiting for pending import jobs to finish"
                end
                if executor
                    executor.shutdown
                    executor.wait_for_termination
                end
            end

            def finalize_package_load(processed_packages, auto_exclude: auto_exclude?)
                manifest = ws.manifest

                all = Set.new
                package_queue = manifest.all_layout_packages(false).each_source_package_name.to_a +
                    processed_packages.map(&:name).to_a
                while !package_queue.empty?
                    pkg_name = package_queue.shift
                    next if all.include?(pkg_name)
                    all << pkg_name

                    next if manifest.ignored?(pkg_name) || manifest.excluded?(pkg_name)

                    pkg_definition = manifest.find_package_definition(pkg_name)
                    pkg = pkg_definition.autobuild
                    if !processed_packages.include?(pkg_definition) && pkg.checked_out?
                        begin
                            manifest.load_package_manifest(pkg.name)
                            process_post_import_blocks(pkg)
                        rescue Exception => e
                            raise if !auto_exclude
                            manifest.exclude_package(pkg.name, "#{pkg.name} had an error when being loaded (#{e.message}) and auto_exclude is true")
                            next
                        end
                    end

                    packages, osdeps = pkg.partition_optional_dependencies
                    packages.each do |dep_pkg_name|
                        if !manifest.ignored?(dep_pkg_name) && !manifest.excluded?(dep_pkg_name)
                            pkg.depends_on dep_pkg_name
                        end
                    end
                    osdeps.each do |osdep_pkg_name|
                        if !manifest.ignored?(osdep_pkg_name) && !manifest.excluded?(osdep_pkg_name)
                            pkg.os_packages << osdep_pkg_name
                        end
                    end

                    if File.directory?(pkg.srcdir)
                        pkg.prepare
                        Rake::Task["#{pkg.name}-prepare"].instance_variable_set(:@already_invoked, true)
                    end
                    pkg.update_environment
                    package_queue.concat(pkg.dependencies)
                end
                all
            end

            def import_packages(selection,
                                non_imported_packages: :checkout,
                                warn_about_ignored_packages: true,
                                warn_about_excluded_packages: true,
                                recursive: true,
                                keep_going: false,
                                install_vcs_packages: Hash.new,
                                auto_exclude: auto_exclude?,
                                **import_options)

                manifest = ws.manifest

                all_processed_packages, failures = import_selected_packages(
                    selection,
                    non_imported_packages: non_imported_packages,
                    keep_going: keep_going,
                    recursive: recursive,
                    install_vcs_packages: install_vcs_packages,
                    auto_exclude: auto_exclude,
                    **import_options)

                if !keep_going && !failures.empty?
                    raise failures.first
                end

                install_internal_dependencies_for(*all_processed_packages)
                finalize_package_load(all_processed_packages, auto_exclude: auto_exclude)

                all_enabled_osdeps = selection.each_osdep_package_name.to_set
                all_enabled_sources = all_processed_packages.map(&:name)
                if recursive
                    all_processed_packages.each do |pkg|
                        all_enabled_osdeps.merge(pkg.autobuild.os_packages)
                    end
                end

                if warn_about_excluded_packages
                    selection.exclusions.each do |sel, pkg_names|
                        pkg_names.sort.each do |pkg_name|
                            Autoproj.warn "#{pkg_name}, which was selected for #{sel}, cannot be built: #{manifest.exclusion_reason(pkg_name)}", :bold
                        end
                    end
                end
                if warn_about_ignored_packages
                    selection.ignores.each do |sel, pkg_names|
                        pkg_names.sort.each do |pkg_name|
                            Autoproj.warn "#{pkg_name}, which was selected for #{sel}, is ignored", :bold
                        end
                    end
                end

                if !failures.empty?
                    raise PackageImportFailed.new(
                        failures, source_packages: all_enabled_sources,
                        osdep_packages: all_enabled_osdeps)
                else
                    return all_enabled_sources, all_enabled_osdeps
                end

            ensure
                if ws.config.import_log_enabled? && Autoproj::Ops::Snapshot.update_log_available?(manifest)
                    update_log_for_processed_packages(all_processed_packages || Array.new, $!)
                end
            end

            def process_post_import_blocks(pkg)
                Autoproj.each_post_import_block(pkg) do |block|
                    block.call(pkg)
                end
            end

            def update_log_for_processed_packages(all_processed_packages, exception)
                all_updated_packages = all_processed_packages.find_all do |processed_pkg|
                    processed_pkg.autobuild.updated?
                end

                if !all_updated_packages.empty?
                    failure_message =
                        if exception
                            " (#{exception.message.split("\n").first})"
                        end
                    ops = Ops::Snapshot.new(ws.manifest, keep_going: true)
                    ops.update_package_import_state(
                        "#{$0} #{ARGV.join(" ")}#{failure_message}",
                        all_updated_packages.map(&:name))
                end
            end
        end
    end
end


