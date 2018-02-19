require 'autoproj/cli/inspection_tool'
require 'autoproj/cli/versions'
require 'autoproj/ops/snapshot'

module Autoproj
    module CLI
        class Commit < InspectionTool
            def default_message(tag_name)
                if tag_name
                    "autoproj created tag #{tag_name}"
                else
                    'autoproj created version commit'
                end
            end

            def run(arguments, options = Hash.new)
                tag_name, *user_selection = *arguments
                ws.load_config
                pkg = ws.manifest.main_package_set.create_autobuild_package
                importer = pkg.importer
                if !importer || !importer.kind_of?(Autobuild::Git)
                    raise CLIInvalidArguments, "cannot use autoproj commit if the main configuration is not managed by git"
                end

                if tag_name
                    begin
                        importer.rev_parse(pkg, "refs/tags/#{tag_name}")
                        raise CLIInvalidArguments, "tag #{tag_name} already exists"
                    rescue Autobuild::PackageException
                    end
                end

                versions_file = File.join(ws.config_dir,
                                          Workspace::OVERRIDES_DIR,
                                          Versions::DEFAULT_VERSIONS_FILE_BASENAME)

                versions = CLI::Versions.new(ws)
                Autoproj.message "creating versions file, this may take a while"
                versions.run(user_selection,
                             save: versions_file,
                             package_sets: options[:package_sets],
                             replace: true,
                             keep_going: options[:keep_going])

                importer.run_git(pkg, 'add', versions_file)
                message = options[:message] || default_message(tag_name)

                importer.run_git(pkg, 'commit', '-m', message)
                importer.run_git(pkg, 'tag', tag_name) unless tag_name.nil?
            end
        end
    end
end

