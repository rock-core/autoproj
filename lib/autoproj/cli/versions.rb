require 'autoproj'
require 'autoproj/cli/inspection_tool'
require 'autoproj/ops/tools'
require 'autoproj/ops/snapshot'

module Autoproj
    module CLI
        class Versions < InspectionTool
            DEFAULT_VERSIONS_FILE_BASENAME = Ops::Snapshot::DEFAULT_VERSIONS_FILE_BASENAME

            def default_versions_file
                File.join( Autoproj.overrides_dir, DEFAULT_VERSIONS_FILE_BASENAME )
            end

            def validate_options(packages, options = Hash.new)
                packages, options = super
                if !options[:save].nil?
                    options[:save] = case options[:save]
                                     when '.'
                                         nil
                                     when 'save'
                                         default_versions_file
                                     else
                                         options[:save].to_str
                                     end
                end
                return packages, options
            end

            def run(user_selection, options)
                initialize_and_load
                packages, *, config_selected =
                    finalize_setup(user_selection,
                                   recursive: options[:deps],
                                   ignore_non_imported_packages: true)
                
                ops = Ops::Snapshot.new(ws.manifest, ignore_errors: options[:keep_going])

                versions = Array.new
                if (config_selected && options[:config] != false) || user_selection.empty?
                    versions += ops.snapshot_package_sets(nil, only_local: options[:only_local])
                end
                if (!config_selected && !options[:config]) || !user_selection.empty?
                    versions += ops.snapshot_packages(packages, nil, only_local: options[:only_local])
                end

                if output_file = options[:save]
                    ops.save_versions(versions, output_file, replace: options[:replace])
                else
                    versions = ops.sort_versions(versions)
                    puts YAML.dump(versions)
                end
            end
        end
    end
end

