require 'autoproj'
require 'autoproj/cli/versions'
require 'autoproj/ops/snapshot'
require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Tag < Base
            def run(tag_name, *user_selection, options = Hash.new)
                pkg = manifest.main_package_set.create_autobuild_package
                importer = pkg.importer
                if !importer || !importer.kind_of?(Autobuild::Git)
                    raise ConfigError, "cannot use autoproj tag if the main configuration is not managed by git"
                end

                versions_file = File.join(
                    Workspace::OVERRIDES_DIR,
                    Versions::DEFAULT_VERSIONS_FILE_BASENAME)

                if tag_name.nil?
                    importer = pkg.importer
                    all_tags = importer.run_git_bare(pkg, 'tag')
                    all_tags.sort.each do |tag|
                        begin importer.show(pkg, "refs/tags/#{tag}", versions_file)
                            puts tag
                        rescue Autobuild::PackageException
                        end
                    end
                    return
                end
                
                # Check if the tag already exists
                begin
                    importer.rev_parse(pkg, "refs/tags/#{tag_name}")
                    raise InvalidArguments, "tag #{tag_name} already exists"
                rescue Autobuild::PackageException
                end

                message = options[:message] ||
                    "autoproj created tag #{tag_name}"
                commit_id = Ops::Snapshot.create_commit(pkg, versions_file, message) do |io|
                    versions = CLI::Versions.new(ws)
                    Autoproj.message "creating versions file, this may take a while"
                    versions.run(user_selection,
                                 package_sets: options[:package_sets],
                                 output_file: io.path,
                                 replace: true,
                                 keep_going: options[:keep_going])
                end

                importer.run_git_bare(pkg, 'tag', tag_name, commit_id)
            end
        end
    end
end

