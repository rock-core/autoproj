require 'autoproj/cli'
require 'autoproj/cli/versions'
module Autoproj
    module CLI
        class Tag
            include Ops::Tools

            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            def parse_options(args)
                options = Hash[package_sets: true, keep_going: false]
                parser = OptionParser.new do |opt|
                    opt.on '--[no-]package-sets', 'commit the package set state as well (enabled by default)' do |flag|
                        options[:package_sets] = flag
                    end
                    opt.on '-k', '--keep-going', "ignore packages that can't be snapshotted (the default is to terminate with an error)" do
                        options[:keep_going] = true
                    end
                    opt.on '-m MESSAGE', '--message=MESSAGE', String, "the message to use for the new commit (defaults to mentioning the tag creation)" do |message|
                        options[:message] = message
                    end
                end
                common_options(parser)
                remaining = parser.parse(args)
                if remaining.size > 1
                    raise InvalidArguments, "expected only the tag name as argument"
                end
                return remaining.first, options
            end

            def run(tag_name, options)
                pkg = manifest.main_package_set.create_autobuild_package
                importer = pkg.importer
                if !importer || !importer.kind_of?(Autobuild::Git)
                    raise ConfigError, "cannot use autoproj tag if the main configuration is not managed by git"
                end

                versions_file = File.join(
                    OVERRIDES_DIR,
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
                    versions = CLI::Versions.new(manifest)
                    Autoproj.message "creating versions file, this may take a while"
                    versions.run(Array.new,
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

