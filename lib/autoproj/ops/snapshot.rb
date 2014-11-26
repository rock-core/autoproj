module Autoproj
    module Ops
    class Snapshot
        # Update version control information with new choices
        #
        # The two parameters are formatted as expected in the version_control
        # and overrides fields in source.yml / overrides.yml, that is (in YAML)
        #
        #   - package_name:
        #     version: '10'
        #     control: '20'
        #     info: '30'
        #
        # The two parameters are expected to only use full package names, and
        # not regular expressions
        #
        # @param [Array<String=>Hash>] overrides the information that should augment
        #   the current state
        # @param [Array<String=>Hash>] state the current state
        # @param [Hash] the updated information
        def self.merge_packets( overrides, state )
            result = overrides.dup
            overriden = overrides.map { |entry| entry.keys.first }.to_set
            state.each do |pkg|
                name, _ = pkg.first
                if !overriden.include?(name)
                    result << pkg
                end
            end
            result
        end

        def self.resolve_selection( user_selection )
            resolved_selection = Autoproj::CmdLine.
                resolve_user_selection(user_selection, :filter => false)
            resolved_selection.filter_excluded_and_ignored_packages(Autoproj.manifest)
            # This calls #prepare, which is required to run build_packages
            packages = Autoproj::CmdLine.import_packages(resolved_selection)

            # Remove non-existing packages
            packages.each do |pkg|
                if !File.directory?(Autoproj.manifest.package(pkg).autobuild.srcdir)
                    raise ConfigError, "cannot commit #{pkg.name} as it is not checked out"
                end
            end
            packages
        end

        def save_versions( versions_file )
            # do a partial update if file exists, and specific packages have
            # been selected
            if selection and File.exists? versions_file
                versions = YAML.load( File.read( versions_file ) )
            else
                versions = {}
            end

            # create direcotry for versions file first
            FileUtils.mkdir_p(File.dirname( versions_file ))

            # augment the versions file with the updated versions
            Snapshot.merge_packets( version_control_info, versions['version_control'] ||= Array.new )
            Snapshot.merge_packets( overrides_info, versions['overrides'] ||= Array.new )

            # write the yaml file
            File.open(versions_file, 'w') do |io|
                io.write YAML.dump(versions)
            end
        end

        def self.snapshot( packages, target_dir )
            # todo
        end

        attr_accessor :version_control_info, :overrides_info, :package_sets

        attr_reader :manifest
        def initialize(manifest)
            @manifest = manifest
        end

        def snapshot_package_sets(target_dir = nil)
            # Pin package sets
            @package_sets = Array.new
            manifest.each_package_set do |pkg_set|
                next if pkg_set.name == 'local'
                if pkg_set.local?
                    @package_sets << Pathname.new(pkg_set.local_dir).
                        relative_path_from(Pathname.new(manifest.file).dirname).
                        to_s
                else
                    vcs_info = pkg_set.vcs.to_hash
                    if pin_info = pkg_set.snapshot(target_dir)
                        vcs_info = vcs_info.merge(pin_info)
                    end
                    @package_sets << vcs_info
                end
            end
        end

        def snapshot_packages(packages, target_dir = nil)
            # Now, create snapshot information for each of the packages
            @version_control_info = []
            @overrides_info = []
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
                        @version_control_info << Hash[package_name, vcs_info]
                    else
                        @overrides_info << Hash[package_name, vcs_info]
                    end
                end
            end

        end

        def snapshot(packages, manifest, target_dir)
            # get the versions information first and snapshot individual 
            # packages.
            # This is done by calling versions again with a target dir
            snapshot_package_sets(target_dir)
            snapshot_packages(target_dir)

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
            manifest_data['package_sets'] = @package_sets
            File.open(manifest_path, 'w') do |io|
                YAML.dump(manifest_data, io)
            end

            # write overrides file
            overrides_path = File.join(target_dir, 'overrides.yml')

            # combine package_set and pkg information
            overrides = Hash.new
            (overrides['version_control'] ||= Array.new).
                concat(@version_control_info)
            (overrides['overrides'] ||= Array.new).
                concat(@overrides_info)

            overrides
            File.open(overrides_path, 'w') do |io|
                io.write YAML.dump(overrides)
            end
        end
    end
    end
end
