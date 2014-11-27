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

        def save_versions( versions, versions_file, options = Hash.new )
            options = Kernel.validate_options options,
                replace: false

            existing_versions = Array.new
            if !options[:replace] && File.exists?(versions_file)
                existing_versions = YAML.load( File.read( versions_file ) ) ||
                    Array.new
            end

            # create direcotry for versions file first
            FileUtils.mkdir_p(File.dirname( versions_file ))

            # augment the versions file with the updated versions
            Snapshot.merge_packets( versions, existing_versions )

            # write the yaml file
            File.open(versions_file, 'w') do |io|
                io.write YAML.dump(versions)
            end
        end

        def self.snapshot( packages, target_dir )
            # todo
        end

        attr_reader :manifest

        # Control what happens if a package fails to be snapshotted
        #
        # If true, the failure to snapshot a package should lead to a warning.
        # Otherwise (the default), it leads to an error.
        #
        # @return [Boolean]
        # @see initialize error_or_warn
        def keep_going?; !!@keep_going end

        def initialize(manifest, options = Hash.new)
            @manifest = manifest
            options = Kernel.validate_options options,
                keep_going: false
            @keep_going = options[:keep_going]
        end

        def snapshot_package_sets(target_dir = nil)
            result = Array.new
            manifest.each_package_set do |pkg_set|
                next if pkg_set.local?

                if vcs_info = pkg_set.snapshot(target_dir)
                    result << Hash[pkg_set.repository_id, vcs_info]
                else
                    error_or_warn(pkg_set, "cannot snapshot #{package_name}: importer snapshot failed")
                end
            end
            result
        end

        def error_or_warn(package, error_msg)
            if keep_going?
                Autoproj.warn error_msg
            else
                raise Autobuild::PackageException.new(package, 'snapshot'), error_msg
            end
        end

        def snapshot_packages(packages, target_dir = nil)
            result = Array.new
            packages.each do |package_name|
                package  = manifest.packages[package_name]
                if !package
                    raise ArgumentError, "#{package_name} is not a known package"
                end
                importer = package.autobuild.importer
                if !importer
                    error_or_warn(package, "cannot snapshot #{package_name} as it has no importer")
                    next
                elsif !importer.respond_to?(:snapshot)
                    error_or_warn(package, "cannot snapshot #{package_name} as the #{importer.class} importer does not support it")
                    next
                end

                vcs_info = importer.snapshot(package.autobuild, target_dir)
                if vcs_info
                    result << Hash[package_name, vcs_info]
                else
                    error_or_warn(package, "cannot snapshot #{package_name}: importer snapshot failed")
                end
            end
            result
        end
        # Create a git commit in which a file contains provided content
        #
        # The target git repository's current index and history is left
        # unmodified. The only modification is the creation of a new dangling
        # commit.
        #
        # It creates a temporary file and gives it to the block so that the file
        # gets filled with the new content
        #
        # @yieldparam [Tempfile] io a temporary file 
        # @param [Autobuild::Package] a package object whose importer is a git
        #   importer. The git commit is created in this repository
        # @param [String] path the file to be created or updated, relative to
        #   the root of the git repository
        # @param [String] the commit message
        # @return [String] the commit ID
        def self.create_commit(pkg, path, message)
            importer = pkg.importer
            object_id = Tempfile.open 'autoproj-versions' do |io|
                yield(io)
                io.flush
                importer.run_git_bare(
                    pkg, 'hash-object', '-w',
                    '--path', path, io.path).first
            end

            # Create the tree using a temporary index in order to not mess with
            # the user's index state. read-tree initializes the new index and
            # then we add the overrides file with update-index / write-tree
            our_index = File.join(importer.git_dir(pkg, false), 'index.autoproj')
            FileUtils.rm_f our_index
            begin
                ENV['GIT_INDEX_FILE'] = our_index
                importer.run_git_bare(pkg, 'read-tree', 'HEAD')
                # And add the new file
                importer.run_git_bare(
                    pkg, 'update-index',
                    '--add', '--cacheinfo', "100644,#{object_id},#{path}")
                tree_id = importer.run_git_bare(pkg, 'write-tree').first
            ensure
                ENV.delete('GIT_INDEX_FILE')
                FileUtils.rm_f our_index
            end

            head_id = importer.rev_parse(pkg, 'HEAD')

            importer.run_git_bare(
                pkg, 'commit-tree',
                tree_id, '-p', head_id, input_streams: [message]).first
        end
    end
    end
end
