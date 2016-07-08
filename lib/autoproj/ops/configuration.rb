module Autoproj
    module Ops
    #--
    # NOTE: indentation is wrong to let git track the history properly
    #+++

    # Implementation of the operations to manage the configuration
    class Configuration
        attr_reader :ws

        # The autoproj install we should update from (if any)
        #
        # @return [nil,InstallationManifest]
        attr_reader :update_from

        # The path in which remote package sets should be exposed to the
        # user
        #
        # @return [String]
        def remotes_dir
            ws.remotes_dir
        end

        # The path in which remote package sets should be exposed to the
        # user
        #
        # @return [String]
        def remotes_user_dir
            File.join(ws.config_dir, "remotes")
        end

        # The path to the main manifest file
        #
        # @return [String]
        def manifest_path
            File.join(ws.config_dir, 'manifest')
        end

        # @param [Manifest] manifest
        # @param [Loader] loader
        # @option options [InstallationManifest] :update_from
        #   another autoproj installation from which we
        #   should update (instead of the normal VCS)
        def initialize(workspace, options = Hash.new)
            options = validate_options options,
                update_from: nil
            @ws = workspace
            @update_from = options[:update_from]
            @remote_update_message_displayed = false
        end

        # Imports or updates a source (remote or otherwise).
        #
        # See create_autobuild_package for informations about the arguments.
        def update_configuration_repository(vcs, name, into, options = Hash.new)
            options = Kernel.validate_options options,
                only_local: false,
                checkout_only: !Autobuild.do_update,
                ignore_errors: false,
                reset: false,
                retry_count: nil

            fake_package = Tools.create_autobuild_package(vcs, name, into)
            if update_from
                # Define a package in the installation manifest that points to
                # the desired folder in other_root
                relative_path = Pathname.new(into).
                    relative_path_from(Pathname.new(root_dir)).to_s
                other_dir = File.join(update_from.path, relative_path)
                if File.directory?(other_dir)
                    update_from.packages.unshift(
                        InstallationManifest::Package.new(fake_package.name, other_dir, File.join(other_dir, 'install')))
                end

                # Then move the importer there if possible
                if fake_package.importer.respond_to?(:pick_from_autoproj_root)
                    if !fake_package.importer.pick_from_autoproj_root(fake_package, update_from)
                        fake_package.update = false
                    end
                else
                    fake_package.update = false
                end
            end
            if retry_count = options.delete(:retry_count)
                fake_package.importer.retry_count = retry_count
            end
            fake_package.import(options)

        rescue Autobuild::ConfigException => e
            raise ConfigError.new, "cannot import #{name}: #{e.message}", e.backtrace
        end

        # Update the main configuration repository
        #
        # @return [Boolean] true if something got updated or checked out,
        #   and false otherwise
        def update_main_configuration(options = Hash.new)
            if !options.kind_of?(Hash)
                options = Hash[only_local: options]
            end
            options = validate_options options,
                only_local: false,
                checkout_only: !Autobuild.do_update,
                ignore_errors: false,
                reset: false,
                retry_count: nil

            update_configuration_repository(
                ws.manifest.vcs,
                "autoproj main configuration",
                ws.config_dir,
                options)
        end

        # Update or checkout a remote package set, based on its VCS definition
        #
        # @param [VCSDefinition] vcs the package set VCS
        # @return [Boolean] true if something got updated or checked out,
        #   and false otherwise
        def update_remote_package_set(vcs, options = Hash.new)
            # BACKWARD
            if !options.kind_of?(Hash)
                options = Hash[only_local: options]
            end
            options = validate_options options,
                only_local: false,
                checkout_only: !Autobuild.do_update,
                ignore_errors: false,
                reset: false,
                retry_count: nil

            name = PackageSet.name_of(ws.manifest, vcs)
            raw_local_dir = PackageSet.raw_local_dir_of(vcs)

            return if options[:checkout_only] && File.exist?(raw_local_dir)

            # YUK. I am stopping there in the refactoring
            # TODO: figure out a better way
            if !@remote_update_message_displayed
                Autoproj.message("autoproj: updating remote definitions of package sets", :bold)
                @remote_update_message_displayed = true
            end
            ws.install_os_packages([vcs.type])
            update_configuration_repository(
                vcs, name, raw_local_dir, options)
        end

        # Create the user-visible directory for a remote package set
        #
        # @param [VCSDefinition] vcs the package set VCS
        # @return [String] the full path to the created user dir
        def create_remote_set_user_dir(vcs)
            name = PackageSet.name_of(ws.manifest, vcs)
            raw_local_dir = PackageSet.raw_local_dir_of(vcs)
            FileUtils.mkdir_p(remotes_user_dir)
            symlink_dest = File.join(remotes_user_dir, name)

            # Check if the current symlink is valid, and recreate it if it
            # is not
            if File.symlink?(symlink_dest)
                dest = File.readlink(symlink_dest)
                if dest != raw_local_dir
                    FileUtils.rm_f symlink_dest
                    Autoproj.create_symlink(raw_local_dir, symlink_dest)
                end
            else
                FileUtils.rm_f symlink_dest
                Autoproj.create_symlink(raw_local_dir, symlink_dest)
            end

            symlink_dest
        end

        def load_package_set(vcs, options, imported_from)
            pkg_set = PackageSet.new(ws.manifest, vcs)
            pkg_set.auto_imports = options[:auto_imports]
            ws.load_if_present(pkg_set, pkg_set.local_dir, 'init.rb')
            pkg_set.load_description_file
            if imported_from
                pkg_set.imported_from << imported_from
                imported_from.imports << pkg_set
            end
            pkg_set
        end

        def queue_auto_imports_if_needed(queue, pkg_set, root_set)
            if pkg_set.auto_imports?
                pkg_set.each_raw_imported_set do |import_vcs, import_options|
                    repository_id = repository_id_of(import_vcs)
                    import_vcs = root_set.overrides_for("pkg_set:#{repository_id}", import_vcs)
                    queue << [import_vcs, import_options, pkg_set]
                end
            end
            queue
        end

        def repository_id_of(vcs)
            if vcs.local?
                return "local:#{vcs.url}"
            end

            vcs.create_autobuild_importer.repository_id
        end

        # Load the package set information
        #
        # It loads the package set information as required by {manifest} and
        # makes sure that they are either updated (if Autobuild.do_update is
        # true), or at least checked out.
        #
        # @yieldparam [String] osdep the name of an osdep required to import the
        #   package sets
        def load_and_update_package_sets(root_pkg_set, options = Hash.new)
            if !options.kind_of?(Hash)
                options = Hash[only_local: options]
            end
            options = validate_options options,
                only_local: false,
                checkout_only: !Autobuild.do_update,
                ignore_errors: false,
                reset: false,
                retry_count: nil

            package_sets = [root_pkg_set]
            by_repository_id = Hash.new
            by_name = Hash.new

            required_remotes_dirs = Array.new

            queue = queue_auto_imports_if_needed(Array.new, root_pkg_set, root_pkg_set)
            while !queue.empty?
                vcs, import_options, imported_from = queue.shift
                repository_id = repository_id_of(vcs)
                if already_processed = by_repository_id[repository_id]
                    already_processed_vcs, already_processed_from, pkg_set = *already_processed
                    if (already_processed_from != root_pkg_set) && (already_processed_vcs != vcs)
                        Autoproj.warn "already loaded the package set from #{already_processed_vcs} from #{already_processed_from.name}, this overrides different settings (#{vcs}) found in #{imported_from.name}"
                    end

                    if imported_from
                        pkg_set.imported_from << imported_from
                        imported_from.imports << pkg_set
                    end
                    next
                end
                by_repository_id[repository_id] = [vcs, imported_from]

                # Make sure the package set has been already checked out to
                # retrieve the actual name of the package set
                if !vcs.local?
                    update_remote_package_set(vcs, options)
                    create_remote_set_user_dir(vcs)
                    raw_local_dir = PackageSet.raw_local_dir_of(vcs)
                    required_remotes_dirs << raw_local_dir
                end

                name = PackageSet.name_of(ws.manifest, vcs)

                required_user_dirs = by_name.collect { |k,v| k }
                Autoproj.debug "Trying to load package_set: #{name} from definition #{repository_id}"
                Autoproj.debug "Already loaded package_sets are: #{required_user_dirs}"

                if already_loaded = by_name[name]
                    already_loaded_pkg_set, already_loaded_vcs = *already_loaded
                    if already_loaded_vcs != vcs
                        if imported_from
                            Autoproj.warn "redundant auto-import by #{imported_from.name} for package set '#{name}'."
                            Autoproj.warn "    A package set with the same name (#{name}) has already been imported from"
                            Autoproj.warn "        #{already_loaded_vcs}"
                            Autoproj.warn "    Skipping the following one: "
                            Autoproj.warn "        #{vcs}"
                        else
                            Autoproj.warn "the manifest refers to a package set from #{vcs}, but a package set with the same name (#{name}) has already been imported from #{already_loaded_vcs}, I am skipping this one"
                        end
                    end

                    if imported_from
                        already_loaded_pkg_set.imported_from << imported_from
                        imported_from.imports << already_loaded_pkg_set
                    end
                    next
                else
                    create_remote_set_user_dir(vcs)
                end

                pkg_set = load_package_set(vcs, import_options, imported_from)
                by_repository_id[repository_id][2] = pkg_set
                package_sets << pkg_set

                by_name[pkg_set.name] = [pkg_set, vcs, options, imported_from]

                # Finally, queue the imports
                queue_auto_imports_if_needed(queue, pkg_set, root_pkg_set)
            end

            required_user_dirs = by_name.collect { |k,v| k }
            cleanup_remotes_dir(package_sets, required_remotes_dirs)
            cleanup_remotes_user_dir(package_sets, required_user_dirs)
            package_sets
        end

        # Removes from {remotes_dir} the directories that do not match a package
        # set
        def cleanup_remotes_dir(package_sets = ws.manifest.package_sets, required_remotes_dirs = Array.new)
            # Cleanup the .remotes and remotes_symlinks_dir directories
            Dir.glob(File.join(remotes_dir, '*')).each do |dir|
                dir = File.expand_path(dir)
                # Once a package set has been checked out during the process,
                # keep it -- so that it won't be checked out again
                if File.directory?(dir) && !required_remotes_dirs.include?(dir)
                    FileUtils.rm_rf dir
                end
            end
        end

        # Removes from {remotes_user_dir} the directories that do not match a
        # package set
        def cleanup_remotes_user_dir(package_sets = ws.manifest.package_sets, required_user_dirs = Array.new)
            Dir.glob(File.join(remotes_user_dir, '*')).each do |file|
                file = File.expand_path(file)
                user_dir = File.basename(file)
                if File.symlink?(file) && !required_user_dirs.include?(user_dir)
                    FileUtils.rm_f file
                end
            end
        end

        def inspect; to_s end

        def sort_package_sets_by_import_order(package_sets, root_pkg_set)
            # The sorting is done in two steps:
            #  - first, we build a topological order of the package sets
            #  - then, we insert the auto-imported packages, following this
            #    topological order, in the user-provided order. Each package is
            #    considered in turn, and added at the earliest place that fits
            #    the dependencies
            topological = Array.new
            queue = package_sets.to_a
            while !queue.empty?
                last_size = queue.size
                pending = queue.dup
                queue = Array.new
                while !pending.empty?
                    pkg_set = pending.shift
                    if pkg_set.imports.any? { |imported_set| !topological.include?(imported_set) }
                        queue.push(pkg_set)
                    else
                        topological << pkg_set
                    end
                end
                if queue.size == last_size
                    raise ArgumentError, "cannot resolve the dependencies between package sets. There seem to be a cycle amongst #{queue.map(&:name).sort.join(", ")}"
                end
            end

            result = root_pkg_set.imports.to_a.dup
            to_insert = topological.dup.
                find_all { |pkg_set| !result.include?(pkg_set) }
            while !to_insert.empty?
                pkg_set = to_insert.shift
                dependencies = pkg_set.imports.dup
                if dependencies.empty?
                    result.unshift(pkg_set)
                else
                    i = result.find_index do |p|
                        dependencies.delete(p)
                        dependencies.empty?
                    end
                    result.insert(i + 1, pkg_set)
                end
            end
            result << root_pkg_set
            result
        end

        def load_package_sets(options = Hash.new)
            options = validate_options options,
                only_local: false,
                checkout_only: true,
                ignore_errors: false,
                reset: false,
                retry_count: nil
            update_configuration(options)
        end

        def update_configuration(options = Hash.new)
            if !options.kind_of?(Hash)
                options = Hash[only_local: options]
            end
            options = validate_options options,
                only_local: false,
                checkout_only: !Autobuild.do_update,
                ignore_errors: false,
                reset: false,
                retry_count: nil

            # Load the installation's manifest a first time, to check if we should
            # update it ... We assume that the OS dependencies for this VCS is already
            # installed (i.e. that the user did not remove it)
            if ws.manifest.vcs && !ws.manifest.vcs.local?
                update_main_configuration(options)
            end
            ws.load_main_initrb
            ws.manifest.load(manifest_path)

            root_pkg_set = ws.manifest.local_package_set
            root_pkg_set.load_description_file
            root_pkg_set.explicit = true
            package_sets = load_and_update_package_sets(root_pkg_set, options)
            root_pkg_set.imports.each do |pkg_set|
                pkg_set.explicit = true
            end
            package_sets = sort_package_sets_by_import_order(package_sets, root_pkg_set)
            package_sets.each do |pkg_set|
                ws.manifest.register_package_set(pkg_set)
            end
            # YUK. I am stopping there in the refactoring
            # TODO: figure out a better way
            if @remote_update_message_displayed
                Autoproj.message
            end
        end
    end
    end
end

