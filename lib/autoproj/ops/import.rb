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

            def import_packages(selection, options = Hash.new)
                options, import_options = Kernel.filter_options options,
                    warn_about_ignored_packages: true,
                    warn_about_excluded_packages: true,
                    recursive: true

                manifest = ws.manifest

                updated_packages = Array.new
                selected_packages = selection.each_source_package_name.map do |pkg_name|
                    manifest.find_autobuild_package(pkg_name)
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

                    # Try to auto-exclude the package early. If the autobuild file
                    # contained some information that allows us to exclude it now,
                    # then let's just do it
                    import_next_step(pkg, reverse_dependencies)
                    if manifest.excluded?(pkg.name)
                        selection.filter_excluded_and_ignored_packages(manifest)
                        next
                    elsif manifest.ignored?(pkg.name)
                        next
                    end

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
                    pkg.import(import_options)
                    if pkg.updated?
                        updated_packages << pkg.name
                    end
                    Rake::Task["#{pkg.name}-import"].instance_variable_set(:@already_invoked, true)
                    manifest.load_package_manifest(pkg.name)

                    # The package setup mechanisms might have added an exclusion
                    # on this package. Handle this.
                    if manifest.excluded?(pkg.name)
                        mark_exclusion_along_revdeps(pkg.name, reverse_dependencies)
                        # Run a filter now, to have errors as early as possible
                        selection.filter_excluded_and_ignored_packages(manifest)
                        # Delete this package from the current_packages set
                        next
                    elsif manifest.ignored?(pkg.name)
                        next
                    end

                    Autoproj.each_post_import_block(pkg) do |block|
                        block.call(pkg)
                    end

                    new_packages = import_next_step(pkg, reverse_dependencies)

                    # Excluded dependencies might have caused the package to be
                    # excluded as well ... do not add any dependency to the
                    # processing queue if it is the case
                    if !manifest.excluded?(pkg.name) && options[:recursive]
                        package_queue.concat(new_packages.sort_by(&:name))
                    end

                    # Verify that everything is still OK with the new
                    # exclusions/ignores
                    selection.filter_excluded_and_ignored_packages(manifest)
                end

                # Now run optional dependency resolution. This is done now, as
                # some optional dependencies might have been excluded during the
                # resolution process above
                #
                # We run this pass on all packages, regardless of the value of
                # 'recursive' or enabled/disabled packages. This is critical
                # by 
                all_enabled_sources, all_enabled_osdeps =
                    Set.new, selection.each_osdep_package_name.to_set
                environment_update_queue = Array.new
                package_queue = selection.each_source_package_name.to_a
                while !package_queue.empty?
                    pkg_name = package_queue.shift
                    next if all_enabled_sources.include?(pkg_name)
                    all_enabled_sources << pkg_name

                    pkg = manifest.find_autobuild_package(pkg_name)
                    packages, osdeps = pkg.partition_optional_dependencies
                    packages.each do |pkg_name|
                        if !manifest.ignored?(pkg_name) && !manifest.excluded?(pkg_name)
                            pkg.depends_on pkg_name
                        end
                    end
                    pkg.os_packages.merge(osdeps)
                    all_enabled_osdeps |= pkg.os_packages

                    pkg.prepare
                    Rake::Task["#{pkg.name}-prepare"].instance_variable_set(:@already_invoked, true)

                    if options[:recursive]
                        package_queue.concat(pkg.dependencies)
                    else
                        environment_update_queue.concat(pkg.dependencies)
                    end
                end

                all_updated_environments = Set.new
                while !environment_update_queue.empty?
                    pkg_name = environment_update_queue.shift
                    next if all_updated_environments.include?(pkg_name)
                    all_updated_environments << pkg_name

                    pkg = manifest.find_autobuild_package(pkg_name)
                    pkg.update_environment

                    if !all_processed_packages.include?(pkg_name)
                        manifest.load_package_manifest(pkg_name)
                    end
                    environment_update_queue.concat(pkg.dependencies)
                end

                if Autoproj.verbose
                    Autoproj.message "autoproj: finished importing packages"
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
                    ops = Ops::Snapshot.new(ws.manifest, keep_going: true)
                    ops.update_package_import_state(
                        "#{$0} #{ARGV.join(" ")}#{failure_message}",
                        updated_packages)
                end
            end
        end
    end
end


