require 'autoproj/cli'
require 'autoproj/cli/versions'

module Autoproj
    module CLI
        class Reset
            include Ops::Tools

            attr_reader :manifest

            def initialize(manifest)
                @manifest = manifest
            end

            def parse_options(args)
                options = Hash[]
                parser = OptionParser.new do |opt|
                    opt.banner = ["autoproj reset COMMIT_ID", "resets the current autoproj installation to the state saved in the given commit ID"].join("\n")
                    opt.on "--freeze", "freezes the project at the requested version" do
                        options[:freeze] = true
                    end
                end
                common_options(parser)
                remaining = parser.parse(args)
                if remaining.empty?
                    puts parser
                    raise InvalidArguments, "expected a reference (tag or log ID) as argument and got nothing"
                elsif remaining.size > 1
                    puts parser
                    raise InvalidArguments, "expected only the tag name as argument"
                end
                return remaining.first, options
            end

            def run(ref_name, options)
                pkg = manifest.main_package_set.create_autobuild_package
                importer = pkg.importer
                if !importer || !importer.kind_of?(Autobuild::Git)
                    raise ConfigError, "cannot use autoproj reset if the main configuration is not managed by git"
                end
                
                # Check if the reflog entry exists
                begin
                    importer.rev_parse(pkg, ref_name)
                rescue Autobuild::PackageException
                    raise InvalidArguments, "#{ref_name} does not exist, run autoproj log for log entries and autoproj tag without arguments for the tags"
                end

                # Checkout the version file
                versions_file = File.join(
                    OVERRIDES_DIR,
                    Versions::DEFAULT_VERSIONS_FILE_BASENAME)
                begin
                    file_data = importer.show(pkg, ref_name, versions_file)
                    versions_path = File.join(Autoproj.config_dir, versions_file)
                    if File.file?(versions_path)
                        old_versions_path = "#{versions_path}.old"
                        FileUtils.rm_f old_versions_path
                        FileUtils.cp versions_path, old_versions_path
                    end
                    FileUtils.mkdir_p File.join(Autoproj.config_dir, OVERRIDES_DIR)
                    File.open(versions_path, 'w') do |io|
                        io.write file_data
                    end
                    system("autoproj", "update", '--reset')

                ensure
                    if !options[:freeze]
                        FileUtils.rm_f versions_path
                        if old_versions_path
                            FileUtils.mv old_versions_path, versions_path
                        end
                    end
                end
            end
        end
    end
end

