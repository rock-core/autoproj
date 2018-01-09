require 'autoproj/cli'
require 'autoproj/cli/inspection_tool'
require 'autoproj/cli/update'
require 'autoproj/cli/versions'

module Autoproj
    module CLI
        class Reset < InspectionTool
            def run(ref_name, options)
                pkg = manifest.main_package_set.create_autobuild_package
                importer = pkg.importer
                if !importer || !importer.kind_of?(Autobuild::Git)
                    raise CLIInvalidArguments, "cannot use autoproj reset if the main configuration is not managed by git"
                end
                
                # Check if the reflog entry exists
                begin
                    importer.rev_parse(pkg, ref_name)
                rescue Autobuild::PackageException
                    raise CLIInvalidArguments, "#{ref_name} does not exist, run autoproj log for log entries and autoproj tag without arguments for the tags"
                end

                # Checkout the version file
                versions_file = File.join(
                    Workspace::OVERRIDES_DIR,
                    Versions::DEFAULT_VERSIONS_FILE_BASENAME)
                begin
                    file_data = importer.show(pkg, ref_name, versions_file)
                    versions_path = File.join(Autoproj.config_dir, versions_file)
                    if File.file?(versions_path)
                        old_versions_path = "#{versions_path}.old"
                        FileUtils.rm_f old_versions_path
                        FileUtils.cp versions_path, old_versions_path
                    end
                    FileUtils.mkdir_p File.join(Autoproj.config_dir, Workspace::OVERRIDES_DIR)
                    File.open(versions_path, 'w') do |io|
                        io.write file_data
                    end

                    update = CLI::Update.new
                    run_args = update.run([], reset: true)

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

