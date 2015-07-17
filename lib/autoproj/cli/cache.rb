require 'autoproj/cli/inspection_tool'
require 'autoproj/ops/cache'

module Autoproj
    module CLI
        class Cache < InspectionTool
            def validate_options(argv, options = Hash.new)
                argv, options = super

                if argv.empty?
                    raise ArgumentError, "expected one cache directory as argument"
                elsif argv.size > 1
                    raise ArgumentError, "expected one cache directory as argument"
                end

                return File.expand_path(argv.first, ws.root_dir), options
            end

            def run(cache_dir, options = Hash.new)
                options = Kernel.validate_options options,
                    keep_going: false,
                    checkout_only: false

                initialize_and_load

                cache_op = Autoproj::Ops::Cache.new(cache_dir, ws.manifest)
                cache_op.create_or_update(options)
            end
        end
    end
end

