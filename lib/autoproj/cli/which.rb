require 'autoproj/cli/inspection_tool'
module Autoproj
    module CLI
        class Which < InspectionTool
            def run(cmd)
                initialize_and_load
                finalize_setup(Array.new)

                puts ws.which(cmd)
            rescue Workspace::ExecutableNotFound => e
                raise CLIInvalidArguments, e.message, e.backtrace
            end
        end
    end
end


