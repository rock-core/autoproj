require 'autoproj/cli/inspection_tool'
module Autoproj
    module CLI
        class Which < InspectionTool
            def run(cmd)
                initialize_and_load
                finalize_setup(Array.new)

                # Resolve the command using the PATH if present
                env = ws.full_env
                absolute =
                    if Pathname.new(cmd).absolute?
                        File.expand_path(cmd)
                    else
                        env.find_in_path(cmd)
                    end

                if absolute
                    if !File.file?(absolute)
                        Autoproj.error "given command `#{absolute}` does not exist"
                        exit 1
                    else
                        puts absolute
                    end
                else
                    Autoproj.error "cannot resolve `#{cmd}` in the workspace"
                    exit 1
                end
            end
        end
    end
end


