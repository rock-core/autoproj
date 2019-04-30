require 'autoproj/find_workspace'
require 'autoproj/ops/cached_env'
require 'autoproj/ops/which'
require 'autoproj/ops/watch'

module Autoproj
    module CLI
        class Exec
            def initialize
                @root_dir = Autoproj.find_workspace_dir
                unless @root_dir
                    require 'autoproj/workspace'
                    # Will do all sorts of error reporting,
                    # or may be able to resolve
                    @root_dir = Workspace.default.root_dir
                end
            end

            def load_cached_env
                env = Ops.load_cached_env(@root_dir)
                return unless env

                Autobuild::Environment.
                    environment_from_export(env, ENV)
            end

            def run(cmd, *args, use_cached_env: Ops.watch_running?(@root_dir))
                env = load_cached_env if use_cached_env

                unless env
                    require 'autoproj'
                    require 'autoproj/cli/inspection_tool'
                    ws = Workspace.from_dir(@root_dir)
                    loader = InspectionTool.new(ws)
                    loader.initialize_and_load
                    loader.finalize_setup(Array.new)
                    env = ws.full_env.resolved_env
                end

                path = env['PATH'].split(File::PATH_SEPARATOR)
                program =
                    begin Ops.which(cmd, path_entries: path)
                    rescue ::Exception => e
                        require 'autoproj'
                        raise CLIInvalidArguments, e.message, e.backtrace
                    end

                begin
                    ::Process.exec(env, program, *args)
                rescue ::Exception => e
                    require 'autoproj'
                    raise CLIInvalidArguments, e.message, e.backtrace
                end
            end
        end
    end
end


