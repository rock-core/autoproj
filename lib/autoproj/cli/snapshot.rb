require 'autoproj'
require 'autoproj/cli/versions'

module Autoproj
    module CLI
        class Snapshot
            include Ops::Tools

            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            def parse_options(args)
                options = Hash.new
                parser = OptionParser.new do |opt|
                    opt.on '-k', '--keep-going', "ignore packages that can't be snapshotted (the default is to terminate with an error)" do
                        options[:keep_going] = true
                    end
                end
                common_options(parser)
                remaining_args = parser.parse(args)
                return remaining_args, options
            end

            def run(target_dir, options)
                # First, copy the configuration directory to create target_dir
                #
                # This must be done first as the snapshot calls might copy stuff in
                # there
                if File.exists?(target_dir)
                    raise ArgumentError, "#{target_dir} already exists"
                end
                FileUtils.cp_r Autoproj.config_dir, target_dir

                begin
                    versions = Versions.new(manifest)
                    versions_file = File.join(
                        target_dir,
                        OVERRIDES_DIR,
                        Versions::DEFAULT_VERSIONS_FILE_BASENAME)

                    versions.run([],
                                 replace: true,
                                 package_sets: true,
                                 keep_going: options[:keep_going],
                                 output_file: versions_file)
                rescue ::Exception
                    FileUtils.rm_rf target_dir
                    raise
                end

                # Finally, remove the remotes/ directory from the generated
                # buildconf, it is obsolete now
                FileUtils.rm_rf File.join(target_dir, 'remotes')

                Autoproj.message "successfully created a snapshot of the current autoproj configuration in #{target_dir}"
            end
        end
    end
end

