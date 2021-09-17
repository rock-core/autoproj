require "autoproj"
require "autoproj/cli/inspection_tool"
require "autoproj/ops/tools"
require "autoproj/ops/snapshot"

module Autoproj
    module CLI
        class Versions < InspectionTool
            DEFAULT_VERSIONS_FILE_BASENAME = Ops::Snapshot::DEFAULT_VERSIONS_FILE_BASENAME

            def default_versions_file
                File.join(ws.overrides_dir, DEFAULT_VERSIONS_FILE_BASENAME)
            end

            def validate_options(packages, options = Hash.new)
                packages, options = super
                unless options[:save].nil?
                    options[:save] = case options[:save]
                                     when "."
                                         nil
                                     when "save"
                                         default_versions_file
                                     else
                                         options[:save].to_str
                                     end
                end
                [packages, options]
            end

            def run(user_selection, options)
                initialize_and_load
                packages, *, config_selected =
                    finalize_setup(user_selection,
                                   recursive: options[:deps])

                ops = Ops::Snapshot.new(ws.manifest, keep_going: options[:keep_going])

                if user_selection.empty?
                    snapshot_package_sets = (options[:config] != false)
                    snapshot_packages = !options[:config]
                elsif config_selected
                    snapshot_package_sets = true
                    snapshot_packages = user_selection.size > 1
                else
                    snapshot_package_sets = options[:config]
                    snapshot_packages = true
                end

                versions = Array.new
                if snapshot_package_sets
                    versions += ops.snapshot_package_sets(nil, only_local: options[:only_local])
                end
                if snapshot_packages
                    versions += ops.snapshot_packages(packages,
                                                      nil,
                                                      only_local: options[:only_local],
                                                      fingerprint: options[:fingerprint])
                end

                if (output_file = options[:save])
                    ops.save_versions(versions, output_file, replace: options[:replace])
                else
                    versions = ops.sort_versions(versions)
                    puts YAML.dump(versions)
                end
            end
        end
    end
end
