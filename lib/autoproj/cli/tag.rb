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
                if remaining.empty?
                    raise InvalidArguments, "expected the tag name as argument"
                elsif remaining.size > 1
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
                
                # Check if the tag already exists
                begin
                    importer.rev_parse(pkg, "refs/tags/#{tag_name}")
                    raise InvalidArguments, "tag #{tag_name} already exists"
                rescue Autobuild::PackageException
                end

                versions_file = File.join(
                    OVERRIDES_DIR,
                    Versions::DEFAULT_VERSIONS_FILE_BASENAME)
                object_id = Tempfile.open 'autoproj-versions' do |io|
                    versions = CLI::Versions.new(manifest)
                    versions.run(Array.new,
                                 package_sets: options[:package_sets],
                                 output_file: io.path,
                                 replace: true,
                                 keep_going: options[:keep_going])

                    importer.run_git_bare(pkg, 'hash-object', '-w',
                        '--path', versions_file, io.path).first.strip
                end

                our_index = File.join(importer.git_dir(pkg, bare: false), 'index.autoproj')
                FileUtils.rm_f our_index
                begin
                    ENV['GIT_INDEX_FILE'] = our_index
                    importer.run_git_bare(pkg, 'update-index',
                        '--add', '--cacheinfo', "100644,#{object_id},#{versions_file}")
                    tree_id = importer.run_git_bare(pkg, 'write-tree').first.strip
                ensure
                    ENV.delete('GIT_INDEX_FILE')
                end

                head_id = importer.rev_parse(pkg, 'HEAD')

                commit_msg = options[:message] ||
                    "autoproj created tag #{tag_name}"
                commit_id = importer.run_git_bare(pkg, 'commit-tree',
                    tree_id, '-p', head_id, input_streams: [commit_msg]).first.strip
                importer.run_git_bare(pkg, 'tag', tag_name, commit_id)
            end
        end
    end
end

