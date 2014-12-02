module Autoproj
    module Ops
    #--
    # NOTE: indentation is wrong to let git track the history properly
    #+++

    # Implementation of the operations to manage the configuration
    class Configuration
        # The manifest object that represents the autoproj configuration
        #
        # @return [Manifest]
        attr_reader :manifest

        # The loader object that should be used to load files such as init.rb
        attr_reader :loader

        # The main configuration directory
        #
        # @return [String]
        attr_reader :config_dir

        # The autoproj install we should update from (if any)
        #
        # @return [nil,InstallationManifest]
        attr_reader :update_from

        # The object that allows us to install OS dependencies
        def osdeps
            Autoproj.osdeps
        end

        # The path in which remote package sets should be exposed to the
        # user
        #
        # @return [String]
        def remotes_dir
            Autoproj.remotes_dir
        end

        # The path in which remote package sets should be exposed to the
        # user
        #
        # @return [String]
        def remotes_user_dir
            File.join(config_dir, "remotes")
        end

        # The path to the main manifest file
        #
        # @return [String]
        def manifest_path
            File.join(config_dir, 'manifest')
        end


        # @param [Manifest] manifest
        # @param [Loader] loader
        # @option options [InstallationManifest] :update_from
        #   (CmdLine.update_from) another autoproj installation from which we
        #   should update (instead of the normal VCS)
        def initialize(manifest, loader, options = Hash.new)
            options = Kernel.validate_options options,
                :update_from => CmdLine.update_from
            @manifest = manifest
            @loader = loader
            @update_from = options[:update_from]
            @config_dir = Autoproj.config_dir
            @remote_update_message_displayed = false
        end

        # Imports or updates a source (remote or otherwise).
        #
        # See create_autobuild_package for informations about the arguments.
        def self.update_configuration_repository(vcs, name, into, options = Hash.new)
            options = Kernel.validate_options options, update_from: nil, only_local: false
            update_from, only_local = options.values_at(:update_from, :only_local)

            fake_package = Tools.create_autobuild_package(vcs, name, into)
            if update_from
                # Define a package in the installation manifest that points to
                # the desired folder in other_root
                relative_path = Pathname.new(into).
                    relative_path_from(Pathname.new(Autoproj.root_dir)).to_s
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
            fake_package.import(only_local)

        rescue Autobuild::ConfigException => e
            raise ConfigError.new, "cannot import #{name}: #{e.message}", e.backtrace
        end

        # Update the main configuration repository
        #
        # @return [Boolean] true if something got updated or checked out,
        #   and false otherwise
        def update_main_configuration(only_local = false)
            self.class.update_configuration_repository(
                manifest.vcs,
                "autoproj main configuration",
                config_dir,
                update_from: update_from,
                only_local: only_local)
        end

        # Update or checkout a remote package set, based on its VCS definition
        #
        # @param [VCSDefinition] vcs the package set VCS
        # @return [Boolean] true if something got updated or checked out,
        #   and false otherwise
        def update_remote_package_set(vcs, only_local = false)
            name = PackageSet.name_of(manifest, vcs)
            raw_local_dir = PackageSet.raw_local_dir_of(vcs)

            return if !Autobuild.do_update && File.exists?(raw_local_dir)

            # YUK. I am stopping there in the refactoring
            # TODO: figure out a better way
            if !@remote_update_message_displayed
                Autoproj.message("autoproj: updating remote definitions of package sets", :bold)
                @remote_update_message_displayed = true
            end
            osdeps.install([vcs.type])
            self.class.update_configuration_repository(
                vcs, name, raw_local_dir,
                update_from: update_from,
                only_local: only_local)
        end

        # Create the user-visible directory for a remote package set
        #
        # @param [VCSDefinition] vcs the package set VCS
        # @return [String] the full path to the created user dir
        def create_remote_set_user_dir(vcs)
            name = PackageSet.name_of(manifest, vcs)
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
            pkg_set = PackageSet.new(manifest, vcs)
            pkg_set.auto_imports = options[:auto_imports]
            loader.load_if_present(pkg_set, pkg_set.local_dir, 'init.rb')
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
        def load_and_update_package_sets(root_pkg_set, only_local = false)
            package_sets = [root_pkg_set]
            by_repository_id = Hash.new
            by_name = Hash.new

            queue = queue_auto_imports_if_needed(Array.new, root_pkg_set, root_pkg_set)
            while !queue.empty?
                vcs, options, imported_from = queue.shift
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

                if !vcs.local?
                    update_remote_package_set(vcs, only_local)
                    create_remote_set_user_dir(vcs)
                end

                name = PackageSet.name_of(manifest, vcs)
                if already_loaded = by_name[name]
                    already_loaded_pkg_set, already_loaded_vcs = *already_loaded
                    if already_loaded_vcs != vcs
                        if imported_from
                            Autoproj.warn "#{imported_from.name} auto-imports a package set from #{vcs}, but a package set with the same name (#{name}) has already been imported from #{already_loaded_vcs}, I am skipping this one"
                        else
                            Autoproj.warn "the manifest refers to a package set from #{vcs}, but a package set with the same name (#{name}) has already been imported from #{already_loaded_vcs}, I am skipping this one"
                        end
                    end

                    if imported_from
                        already_loaded_pkg_set.imported_from << imported_from
                        imported_from.imports << already_loaded_pkg_set
                    end
                    next
                end

                pkg_set = load_package_set(vcs, options, imported_from)
                by_repository_id[repository_id][2] = pkg_set
                package_sets << pkg_set

                by_name[pkg_set.name] = [pkg_set, vcs, options, imported_from]

                # Finally, queue the imports
                queue_auto_imports_if_needed(queue, pkg_set, root_pkg_set)
            end

            cleanup_remotes_dir(package_sets)
            cleanup_remotes_user_dir(package_sets)
            package_sets
        end

        # Removes from {remotes_dir} the directories that do not match a package
        # set
        def cleanup_remotes_dir(package_sets = manifest.package_sets)
            # Cleanup the .remotes and remotes_symlinks_dir directories
            Dir.glob(File.join(remotes_dir, '*')).each do |dir|
                dir = File.expand_path(dir)
                if File.directory?(dir) && !package_sets.find { |pkg| pkg.raw_local_dir == dir }
                    FileUtils.rm_rf dir
                end
            end
        end

        # Removes from {remotes_user_dir} the directories that do not match a
        # package set
        def cleanup_remotes_user_dir(package_sets = manifest.package_sets)
            Dir.glob(File.join(remotes_user_dir, '*')).each do |file|
                file = File.expand_path(file)
                if File.symlink?(file) && !package_sets.find { |pkg_set| pkg_set.user_local_dir == file }
                    FileUtils.rm_f file
                end
            end
        end

        def sort_package_sets_by_import_order(package_sets, root_pkg_set)
            # We do not consider the 'standalone' package sets while sorting.
            # They are taken care of later, as we need to maintain the order the
            # user defined in the package_sets section of the manifest
            queue = package_sets.flat_map do |pkg_set|
                if (!pkg_set.imports.empty? || !pkg_set.explicit?) && !(pkg_set == root_pkg_set)
                    [pkg_set] + pkg_set.imports.to_a
                else []
                end
            end.to_set.to_a

            sorted = Array.new
            while !queue.empty?
                pkg_set = queue.shift
                if pkg_set.imports.any? { |imported_set| !sorted.include?(imported_set) }
                    queue.push(pkg_set)
                else
                    sorted << pkg_set
                end
            end

            # We now need to re-add the standalone package sets. Their order is
            # determined by the order in the package_set section of the manifest
            #
            # Concretely, we add them in order, just after the entry above them
            previous = nil
            root_pkg_set.imports.each do |explicit_pkg_set|
                if !sorted.include?(explicit_pkg_set)
                    if !previous
                        sorted.unshift explicit_pkg_set
                    else
                        i = sorted.index(previous)
                        sorted.insert(i + 1, explicit_pkg_set)
                    end
                end
                previous = pkg_set
            end

            sorted << root_pkg_set
            sorted
        end

        def update_configuration(only_local = false)
            # Load the installation's manifest a first time, to check if we should
            # update it ... We assume that the OS dependencies for this VCS is already
            # installed (i.e. that the user did not remove it)
            if manifest.vcs && !manifest.vcs.local?
                update_main_configuration(only_local)
            end
            Tools.load_main_initrb(manifest)
            manifest.load(manifest_path)

            root_pkg_set = LocalPackageSet.new(manifest)
            root_pkg_set.load_description_file
            root_pkg_set.explicit = true
            package_sets = load_and_update_package_sets(root_pkg_set, only_local)
            root_pkg_set.imports.each do |pkg_set|
                pkg_set.explicit = true
            end
            package_sets = sort_package_sets_by_import_order(package_sets, root_pkg_set)
            package_sets.each do |pkg_set|
                manifest.register_package_set(pkg_set)
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

