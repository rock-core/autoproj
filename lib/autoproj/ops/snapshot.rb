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
            def self.merge_packets(overrides, state)
                overriden = overrides.map { |entry| entry.keys.first }.to_set
                filtered_state = state.find_all do |pkg|
                    name, = pkg.first
                    !overriden.include?(name)
                end
                filtered_state + overrides
            end

            def self.update_log_available?(manifest)
                new(manifest).import_state_log_package
                true
            rescue ArgumentError
                false
            end

            def sort_versions(versions)
                pkg_sets, pkgs = versions.partition { |vcs| vcs.keys.first =~ /^pkg_set:/ }
                pkg_sets.sort_by { |vcs| vcs.keys.first } +
                    pkgs.sort_by { |vcs| vcs.keys.first }
            end

            def save_versions(versions, versions_file, replace: false)
                existing_versions = Array.new
                if !replace && File.exist?(versions_file)
                    existing_versions = YAML.load(File.read(versions_file)) ||
                                        Array.new
                end

                # create direcotry for versions file first
                FileUtils.mkdir_p(File.dirname(versions_file))

                # augment the versions file with the updated versions
                versions = Snapshot.merge_packets(versions, existing_versions)

                versions = sort_versions(versions)

                # write the yaml file
                File.open(versions_file, "w") do |io|
                    io.write YAML.dump(versions)
                end
            end

            def self.snapshot(packages, target_dir)
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
            def keep_going?
                !!@keep_going
            end

            def initialize(manifest, keep_going: false)
                @manifest = manifest
                @keep_going = keep_going
            end

            def snapshot_package_sets(target_dir = nil, only_local: true)
                result = Array.new
                manifest.each_package_set do |pkg_set|
                    next if pkg_set.local?

                    vcs_info =
                        begin pkg_set.snapshot(target_dir, only_local: only_local)
                        rescue Exception => e
                            error_or_warn(pkg_set, e)
                            next
                        end

                    if vcs_info
                        result << Hash["pkg_set:#{pkg_set.repository_id}", vcs_info]
                    else
                        error_or_warn(pkg_set, "cannot snapshot package set #{pkg_set.name}: importer snapshot failed")
                    end
                end
                result
            end

            def error_or_warn(package, error)
                if error.kind_of?(Interrupt)
                    raise
                elsif keep_going?
                    error = error.message unless error.respond_to?(:to_str)
                    Autoproj.warn error
                elsif error.respond_to?(:to_str)
                    raise Autobuild::PackageException.new(package, "snapshot"), error
                else
                    raise
                end
            end

            def snapshot_packages(packages, target_dir = nil, only_local: true, fingerprint: false)
                result = Array.new
                fingerprint_memo = Hash.new
                packages.each do |package_name|
                    package = manifest.find_package_definition(package_name)
                    unless package
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

                    vcs_info =
                        begin importer.snapshot(package.autobuild, target_dir, only_local: only_local)
                        rescue Exception => e
                            error_or_warn(package, e)
                            next
                        end

                    if fingerprint
                        vcs_info["fingerprint"] = package.autobuild.fingerprint(memo: fingerprint_memo)
                    end

                    if vcs_info
                        result << Hash[package_name, vcs_info]
                    else
                        error_or_warn(package, "cannot snapshot #{package_name}: importer snapshot failed")
                    end
                end
                result
            end

            # Returns the list of existing version tags
            def tags(package)
                importer = package.importer
                all_tags = importer.run_git_bare(package, "tag")
                all_tags.find_all do |tag_name|
                end
            end

            # Returns a package that is used to store this installs import history
            #
            # Its importer is guaranteed to be a git importer
            #
            # @return [Autobuild::Package] a package whose importer is
            #   {Autobuild::Git}
            def import_state_log_package
                pkg = manifest.main_package_set.create_autobuild_package
                unless pkg.importer
                    if Autobuild::Git.can_handle?(pkg.srcdir)
                        pkg.importer = Autobuild.git(pkg.srcdir)
                    end
                end

                unless pkg.importer.kind_of?(Autobuild::Git)
                    raise ArgumentError, "cannot use autoproj auto-import feature if the main configuration is not managed under git"
                end

                pkg
            end

            def self.import_state_log_ref
                "refs/autoproj"
            end

            DEFAULT_VERSIONS_FILE_BASENAME = "50-versions.yml"

            def import_state_log_file
                File.join(Workspace::OVERRIDES_DIR, DEFAULT_VERSIONS_FILE_BASENAME)
            end

            def current_import_state
                main = import_state_log_package
                # Try to resolve the log ref, and extract the version file from it
                begin
                    yaml = main.importer.show(main, self.class.import_state_log_ref, import_state_log_file)
                    YAML.load(yaml) || Array.new
                rescue Autobuild::PackageException
                    Array.new
                end
            end

            def update_package_import_state(name, packages)
                current_versions = current_import_state
                if current_versions.empty?
                    # Do a full snapshot this time only
                    Autoproj.message "  building initial autoproj import log, this may take a while"
                    packages = manifest.all_selected_source_packages
                                       .find_all { |pkg| File.directory?(pkg.autobuild.srcdir) }
                                       .map(&:name)
                end
                versions  = snapshot_package_sets
                versions += snapshot_packages(packages)
                versions = Snapshot.merge_packets(versions, current_versions)
                save_import_state(name, versions)
            end

            def save_import_state(name, versions)
                versions = sort_versions(versions)

                main = import_state_log_package
                git_dir = main.importer.git_dir(main, false)
                # Ensure that our ref is being logged
                FileUtils.touch File.join(git_dir, "logs", *self.class.import_state_log_ref.split("/"))
                # Create the commit with the versions info
                commit_id = Snapshot.create_commit(main, import_state_log_file, name, real_author: false) do |io|
                    YAML.dump(versions, io)
                end
                # And save it in our reflog
                main.importer.run_git_bare(main, "update-ref", "-m", name, self.class.import_state_log_ref, commit_id)
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
            def self.create_commit(pkg, path, message, parent_id = nil, real_author: true)
                importer = pkg.importer
                object_id = Tempfile.open "autoproj-versions" do |io|
                    yield(io)
                    io.flush
                    importer.run_git_bare(
                        pkg, "hash-object", "-w",
                        "--path", path, io.path
                    ).first
                end

                cacheinfo = ["100644", object_id, path]
                cacheinfo = cacheinfo.join(",") if Autobuild::Git.at_least_version(2, 1)

                parent_id ||= importer.rev_parse(pkg, "HEAD")

                env = Hash.new
                unless real_author
                    env["GIT_AUTHOR_NAME"] = "autoproj"
                    env["GIT_AUTHOR_EMAIL"] = "autoproj"
                    env["GIT_COMMITTER_NAME"] = "autoproj"
                    env["GIT_COMMITTER_EMAIL"] = "autoproj"
                end

                # Create the tree using a temporary index in order to not mess with
                # the user's index state. read-tree initializes the new index and
                # then we add the overrides file with update-index / write-tree
                our_index = File.join(importer.git_dir(pkg, false), "index.autoproj")
                FileUtils.rm_f our_index
                begin
                    ENV["GIT_INDEX_FILE"] = our_index
                    importer.run_git_bare(pkg, "read-tree", parent_id)
                    # And add the new file
                    importer.run_git_bare(
                        pkg, "update-index",
                        "--add", "--cacheinfo", *cacheinfo
                    )
                    tree_id = importer.run_git_bare(pkg, "write-tree").first
                ensure
                    ENV.delete("GIT_INDEX_FILE")
                    FileUtils.rm_f our_index
                end

                importer.run_git_bare(
                    pkg, "commit-tree",
                    tree_id, "-p", parent_id, env: env, input_streams: [message]
                ).first
            end
        end
    end
end
