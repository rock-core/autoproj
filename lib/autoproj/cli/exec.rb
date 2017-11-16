require 'autoproj/cli/inspection_tool'
module Autoproj
    module CLI
        class Exec < InspectionTool
            def run(cmd, *args)
                initialize_and_load
                finalize_setup(Array.new)

                # Resolve the command using the PATH if present
                env = ws.full_env
                if !File.file?(cmd)
                    cmd = env.find_in_path(cmd) || cmd
                end
                exec(env.resolved_env, cmd, *args)
            end
        end
    end
end


