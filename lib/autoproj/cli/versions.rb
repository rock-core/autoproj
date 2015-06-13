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
                if options.has_key?(:save)
                    options[:save] = case options[:save]
                                     when '.'
                                         nil
                                     when true
                                         default_versions_file
                                     else
                                         options[:save].to_str
                                     end
                end
                return packages, options
            end

            def run(user_selection, options)
                initialize_and_load
                packages, resolved_selection, config_selected =
                    finalize_setup(user_selection,
                                   ignore_non_imported_packages: true)

                if (config_selected || user_selection.empty?) && (options[:package_sets] != false)
                    options[:package_sets] = true
                end

                ops = Ops::Snapshot.new(ws.manifest, keep_going: options[:keep_going])

                versions = Array.new
                if options[:package_sets]
                    versions += ops.snapshot_package_sets
                end
                versions += ops.snapshot_packages(packages)
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

