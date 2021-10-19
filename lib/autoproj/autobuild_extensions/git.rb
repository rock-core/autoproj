module Autoproj
    module AutobuildExtensions
        module Git
            # Reconfigures this importer to use an already existing checkout located
            # in the given autoproj root
            #
            # @param [Autobuild::Package] the package we are dealing with
            # @param [Autoproj::InstallationManifest] the other root's installation
            #   manifest
            def pick_from_autoproj_root(package, installation_manifest)
                other_pkg = installation_manifest[package.name]
                return if !other_pkg || !File.directory?(other_pkg.srcdir)

                relocate(other_pkg.srcdir)
                true
            end

            # Get version information
            #
            # @option options [Boolean] local (true) whether the snapshot should access
            #   the remote repository to determine if the local commit is there, and
            #   determine what would be the best remote branch, or stick to information
            #   that is present locally
            # @option options [Boolean] exact_state (true) whether the snapshot should
            #   point to a specific commit (either with a tag or with a commit ID), or
            #   only override the branch
            # @return [Hash] the snapshot information, in a format that can be used by
            #   {#relocate}
            def snapshot(package, target_dir = nil, only_local: true, exact_state: true)
                if only_local
                    snapshot_local(package, exact_state: exact_state)
                else
                    snapshot_against_remote(package, exact_state: exact_state)
                end
            end

            def normalize_branch_name(name)
                if name =~ /^refs\/heads\//
                    name
                else
                    "refs/heads/#{name}"
                end
            end

            # Returns true if the given snapshot information is different from the
            # configured importer state
            #
            # It tests only against the parameters returned by {#snapshot}
            def snapshot_overrides?(snapshot)
                # We have to normalize the branch and tag names
                if (snapshot_local = snapshot["local_branch"] || snapshot["branch"])
                    snapshot_local = normalize_branch_name(snapshot_local)
                    local_branch = normalize_branch_name(self.local_branch)
                    return true if snapshot_local != local_branch
                end
                if (snapshot_remote = snapshot["remote_branch"] || snapshot["branch"])
                    snapshot_remote = normalize_branch_name(snapshot_remote)
                    remote_branch  = normalize_branch_name(self.remote_branch)
                    return true if snapshot_remote != remote_branch
                end
                if (snapshot_id = snapshot["commit"])
                    return true if commit != snapshot_id
                end
                false
            end

            # @api private
            def snapshot_against_remote(package, options = Hash.new)
                info = Hash["tag" => nil, "commit" => nil]
                remote_revname = describe_commit_on_remote(package, "HEAD", tags: options[:exact_state])

                case remote_revname
                when /^refs\/heads\/(.*)/
                    remote_branch = $1
                    if local_branch == remote_branch
                        info["branch"] = local_branch
                    else
                        info["local_branch"] = local_branch
                        info["remote_branch"] = remote_branch
                    end
                when /^refs\/tags\/(.*)/
                    info["tag"] = $1
                else
                    info["local_branch"] = local_branch
                    info["remote_branch"] = remote_revname
                end

                if options[:exact_state] && !info["tag"]
                    info["commit"] = rev_parse(package, "HEAD")
                end
                info
            end

            # @api private
            def snapshot_local(package, options = Hash.new)
                info = Hash.new
                if local_branch == remote_branch
                    info["branch"] = branch
                else
                    info["local_branch"] = local_branch
                    info["remote_branch"] = remote_branch
                end

                if options[:exact_state]
                    has_tag, described = describe_rev(package, "HEAD")
                    if has_tag
                        info["tag"] = described
                        info["commit"] = nil
                    else
                        info["tag"] = nil
                        info["commit"] = described
                    end
                end
                info
            end
        end
    end
end
