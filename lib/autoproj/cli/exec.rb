require 'autoproj/cli/inspection_tool'
module Autoproj
    module CLI
        class Exec < InspectionTool
            def run(cmd, *args)
                initialize_and_load
                finalize_setup(Array.new)

                program = 
                    begin ws.which(cmd)
                    rescue ::Exception => e
                        raise CLIInvalidArguments, e.message, e.backtrace
                    end
                env = ws.full_env.resolved_env

                begin
                    ::Process.exec(env, program, *args)
                rescue ::Exception => e
                    raise CLIInvalidArguments, e.message, e.backtrace
                end
            end
        end
    end
end


