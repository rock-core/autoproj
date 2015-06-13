require 'autoproj'
require 'autoproj/cli/versions'
require 'autoproj/ops/snapshot'
require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Commit < InspectionTool
            def run(*user_selection, options = Hash.new)
                pkg = manifest.main_package_set.create_autobuild_package
                importer = pkg.importer
                if !importer || !importer.kind_of?(Autobuild::Git)
                    raise ConfigError, "cannot use autoproj tag if the main configuration is not managed by git"
                end

                versions_file = File.join(
                    ws.config_dir,
                    Workspace::OVERRIDES_DIR,
                    Versions::DEFAULT_VERSIONS_FILE_BASENAME)

                initialize_and_load

                versions = CLI::Versions.new(ws)
                Autoproj.message "creating versions file, this may take a while"
                versions.run(user_selection,
                             save: File.join(ws.config_dir, versions_file),
                             package_sets: options[:package_sets],
                             output_file: io.path,
                             replace: true,
                             keep_going: options[:keep_going])

                importer.run_git(pkg, 'add', versions_file)
                message = options[:message] ||
                    "autoproj created tag #{tag_name}"

                importer.run_git(pkg, 'commit', '-m', message)
            end
        end
    end
end

