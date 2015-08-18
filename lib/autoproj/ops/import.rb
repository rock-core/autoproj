module Autoproj
    module Ops
        class Import
            attr_reader :ws
            def initialize(ws)
                @ws = ws
            end

            def mark_exclusion_along_revdeps(pkg_name, revdeps, chain = [], reason = nil)
                root = !reason
                chain.unshift pkg_name
                if root
                    reason = ws.manifest.exclusion_reason(pkg_name)
                else
                    if chain.size == 1
                        ws.manifest.add_exclusion(pkg_name, "its dependency #{reason}")
                    else
                        ws.manifest.add_exclusion(pkg_name, "#{reason} (dependency chain: #{chain.join(">")})")
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
                [OSDependencies::AVAILABLE, OSDependencies::IGNORE]

            def import_next_step(pkg, reverse_dependencies)
                new_packages = []
                pkg.dependencies.each do |dep_name|
                    reverse_dependencies[dep_name] << pkg.name
                    new_packages << ws.manifest.find_autobuild_package(dep_name)
                end
                pkg_opt_deps, pkg_opt_os_deps = pkg.partition_optional_dependencies
                pkg_opt_deps.each do |dep_name|
                    new_packages << ws.manifest.find_autobuild_package(dep_name)
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
                elsif pkg.importer
                    true
                end
            end

            def post_package_import(selection, manifest, pkg, reverse_dependencies)
                Rake::Task["#{pkg.name}-import"].instance_variable_set(:@already_invoked, true)
                manifest.load_package_manifest(pkg.name)

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
                    Autoproj.each_post_import_block(pkg) do |block|
                        block.call(pkg)
                    end
                    import_next_step(pkg, reverse_dependencies)
                end
            end

            class ImportFailed < RuntimeError; end

            # Import all packages from the given selection, and their
            # dependencies
            def import_selected_packages(selection, updated_packages, options = Hash.new)
                all_processed_packages = Set.new

                parallel_options, options = Kernel.filter_options options,
                    parallel: ws.config.parallel_import_level

                # This is used in the ensure block, initialize as early as
                # possible
                executor = Concurrent::FixedThreadPool.new(parallel_options[:parallel], max_length: 0)

                options, import_options = Kernel.filter_options options,
                    recursive: true,
                    retry_count: nil

                ignore_errors = options[:ignore_errors]
                retry_count = options[:retry_count]
                manifest = ws.manifest

                selected_packages = selection.each_source_package_name.map do |pkg_name|
                    manifest.find_autobuild_package(pkg_name)
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
                interactive_imports = Array.new
                package_queue = selected_packages.to_a.sort_by(&:name)
                failures = Hash.new
                while failures.empty? || ignore_errors
                    # Queue work for all packages in the queue
                    package_queue.each do |pkg|
                        # Remove packages that have already been processed
                        next if all_processed_packages.include?(pkg)
                        all_processed_packages << pkg

                        if !pre_package_import(selection, manifest, pkg, reverse_dependencies)
                            next
                        elsif pkg.importer.interactive?
                            interactive_imports << pkg
                            next
                        end

                        pending_packages << pkg
                        import_future = Concurrent::Future.new(executor: executor, args: [pkg]) do |import_pkg|
                            ## COMPLETELY BYPASS RAKE HERE
                            # The reason is that the ordering of import/prepare between
                            # packages is not important BUT the ordering of import vs.
                            # prepare in one package IS important: prepare is the method
                            # that takes into account dependencies.
                            if retry_count
                                import_pkg.importer.retry_count = retry_count
                            end
                            import_pkg.import(import_options.merge(allow_interactive: false))
                        end
                        import_future.add_observer do |time, result, reason|
                            completion_queue << [pkg, time, result, reason]
                        end
                        import_future.execute
                    end
                    package_queue.clear

                    if completion_queue.empty? && pending_packages.empty?
                        # We've nothing to process anymore ... process
                        # interactive imports if there are some. Otherwise,
                        # we're done
                        if interactive_imports.empty?
                            return all_processed_packages
                        else
                            interactive_imports.each do |pkg|
                                begin
                                    result = pkg.import(import_options.merge(allow_interactive: true))
                                rescue Exception => reason
                                end
                                completion_queue << [pkg, Time.now, result, reason]
                            end
                            interactive_imports.clear
                        end
                    end

                    # And wait one to finish
                    pkg, time, result, reason = completion_queue.pop
                    pending_packages.delete(pkg)
                    if reason
                        if reason.kind_of?(Autobuild::InteractionRequired)
                            interactive_imports << pkg
                        else
                            # One importer failed... terminate
                            Autoproj.error "import of #{pkg.name} failed"
                            if !reason.kind_of?(Interrupt)
                                Autoproj.error "#{reason}"
                            end
                            failures[pkg] = reason
                        end
                    else
                        if new_packages = post_package_import(selection, manifest, pkg, reverse_dependencies)
                            # Excluded dependencies might have caused the package to be
                            # excluded as well ... do not add any dependency to the
                            # processing queue if it is the case
                            if manifest.excluded?(pkg.name)
                                selection.filter_excluded_and_ignored_packages(manifest)
                            elsif options[:recursive]
                                package_queue = new_packages.sort_by(&:name)
                            end
                        end
                    end
                end

                if !failures.empty?
                    raise ImportFailed, "import of #{failures.size} packages failed: #{failures.keys.map(&:name).sort.join(", ")}"
                end

                all_processed_packages

            ensure
                if failures && !failures.empty? && !ignore_errors
                    Autoproj.error "waiting for pending import jobs to finish"
                end
                if executor
                    executor.shutdown
                    executor.wait_for_termination
                end
                updated_packages.concat(all_processed_packages.find_all(&:updated?).map(&:name))
            end
            
            def finalize_package_load(processed_packages)
                manifest = ws.manifest

                all = Set.new
                package_queue = manifest.all_layout_packages(false).each_source_package_name.to_a +
                    processed_packages.map(&:name).to_a
                while !package_queue.empty?
                    pkg_name = package_queue.shift
                    next if all.include?(pkg_name)
                    all << pkg_name

                    next if manifest.ignored?(pkg_name) || manifest.excluded?(pkg_name)

                    pkg = manifest.find_autobuild_package(pkg_name)
                    if !processed_packages.include?(pkg) && File.directory?(pkg.srcdir)
                        manifest.load_package_manifest(pkg.name)
                        Autoproj.each_post_import_block(pkg) do |block|
                            block.call(pkg)
                        end
                    end

                    packages, osdeps = pkg.partition_optional_dependencies
                    packages.each do |pkg_name|
                        if !manifest.ignored?(pkg_name) && !manifest.excluded?(pkg_name)
                            pkg.depends_on pkg_name
                        end
                    end
                    pkg.os_packages.merge(osdeps)
                    pkg.prepare
                    Rake::Task["#{pkg.name}-prepare"].instance_variable_set(:@already_invoked, true)
                    pkg.update_environment
                    package_queue.concat(pkg.dependencies)
                end
                all
            end

            def import_packages(selection, options = Hash.new)
                # Used in the ensure block, initialize as soon as possible
                updated_packages = Array.new

                options, import_options = Kernel.filter_options options,
                    warn_about_ignored_packages: true,
                    warn_about_excluded_packages: true,
                    recursive: true

                manifest = ws.manifest

                all_processed_packages = import_selected_packages(
                    selection, updated_packages, import_options.merge(recursive: options[:recursive]))
                finalize_package_load(all_processed_packages)

                all_enabled_osdeps = selection.each_osdep_package_name.to_set
                all_enabled_sources = all_processed_packages.map(&:name)
                if options[:recursive]
                    all_processed_packages.each do |pkg|
                        all_enabled_osdeps.merge(pkg.os_packages)
                    end
                end

                if options[:warn_about_excluded_packages]
                    selection.exclusions.each do |sel, pkg_names|
                        pkg_names.sort.each do |pkg_name|
                            Autoproj.warn "#{pkg_name}, which was selected for #{sel}, cannot be built: #{manifest.exclusion_reason(pkg_name)}", :bold
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

                return all_enabled_sources, all_enabled_osdeps

            ensure
                if ws.config.import_log_enabled? && !updated_packages.empty? && Autoproj::Ops::Snapshot.update_log_available?(manifest)
                    failure_message =
                        if $!
                            " (#{$!.message.split("\n").first})"
                        end
                    ops = Ops::Snapshot.new(ws.manifest, ignore_errors: true)
                    ops.update_package_import_state(
                        "#{$0} #{ARGV.join(" ")}#{failure_message}",
                        updated_packages)
                end
            end
        end
    end
end


