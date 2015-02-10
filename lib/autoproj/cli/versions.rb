require 'autoproj'
require 'autoproj/cmdline'
require 'autoproj/ops/tools'
require 'autoproj/ops/snapshot'

module Autoproj
    module CLI
        class Versions
            include Ops::Tools

            DEFAULT_VERSIONS_FILE_BASENAME = Ops::Snapshot::DEFAULT_VERSIONS_FILE_BASENAME

            def default_versions_file
                File.join( Autoproj.overrides_dir, DEFAULT_VERSIONS_FILE_BASENAME )
            end

            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            def resolve_selection( user_selection )
                resolved_selection = CmdLine.
                    resolve_user_selection(user_selection, :filter => false)
                resolved_selection.filter_excluded_and_ignored_packages(manifest)
                # This calls #prepare, which is required to run build_packages
                packages = CmdLine.import_packages(resolved_selection)

                # Remove non-existing packages
                packages.each do |pkg|
                    if !File.directory?(manifest.package(pkg).autobuild.srcdir)
                        raise ConfigError, "cannot commit #{pkg} as it is not checked out"
                    end
                end
                packages
            end


            def parse_options(args)
                options = Hash.new
                parser = OptionParser.new do |opt|
                    opt.on '--[no-]package-sets', 'commit the package set state as well (default if no packages are selected)' do |flag|
                        options[:package_sets] = flag
                    end
                    opt.on '--replace', String, 'if the file given to --save exists, replace it instead of updating it' do
                        options[:replace] = true
                    end
                    opt.on '-k', '--keep-going', "ignore packages that can't be snapshotted (the default is to terminate with an error)" do
                        options[:keep_going] = true
                    end
                    opt.on '--save[=FILE]', String, "the file into which the versions should be saved (if no file is given, defaults to #{default_versions_file})" do |file|
                        options[:output_file] =
                            if file == '-'
                                nil
                            elsif !file
                                default_versions_file
                            else
                                file
                            end
                    end
                end
                common_options(parser)
                remaining = parser.parse(args)
                return remaining, options
            end

            def run(user_selection, options)
                do_package_sets = options[:package_sets]
                if do_package_sets.nil? && user_selection.empty?
                    do_package_sets = true
                end

                CmdLine.report(silent: true) do
                    packages = resolve_selection user_selection
                    ops = Ops::Snapshot.new(manifest, keep_going: options[:keep_going])

                    versions = Array.new
                    if do_package_sets
                        versions += ops.snapshot_package_sets
                    end
                    versions += ops.snapshot_packages(packages)
                    if output_file = options[:output_file]
                        ops.save_versions(versions, output_file, replace: options[:replace])
                    else
                        versions = ops.sort_versions(versions)
                        puts YAML.dump(versions)
                    end
                end
            end
        end
    end
end

