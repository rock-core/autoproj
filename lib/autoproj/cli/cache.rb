require 'autoproj/cli/inspection_tool'
require 'autoproj/ops/cache'

module Autoproj
    module CLI
        class Cache < InspectionTool
            def validate_options(argv, options = Hash.new)
                argv, options = super

                if argv.empty?
                    default_cache_dirs = Autobuild::Importer.default_cache_dirs
                    if !default_cache_dirs || default_cache_dirs.empty?
                        raise ArgumentError, "no cache directory defined with e.g. the AUTOBUILD_CACHE_DIR environment variable, expected one cache directory as argument"
                    end
                    Autoproj.warn "using cache directory #{default_cache_dirs.first} from the autoproj configuration"
                    argv << default_cache_dirs.first
                elsif argv.size > 1
                    raise ArgumentError, "expected only one cache directory as argument"
                end

                return File.expand_path(argv.first, ws.root_dir), options
            end

            def run(cache_dir, options = Hash.new)
                options = Kernel.validate_options options,
                    keep_going: false,
                    checkout_only: false

                initialize_and_load
                finalize_setup

                cache_op = Autoproj::Ops::Cache.new(cache_dir, ws.manifest)
                cache_op.create_or_update(options)
            end
        end
    end
end

