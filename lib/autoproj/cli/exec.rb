require "autoproj/find_workspace"
require "autoproj/ops/cached_env"
require "autoproj/ops/which"
require "autoproj/ops/watch"

module Autoproj
    module CLI
        class Exec
            def initialize
                @root_dir = Autoproj.find_workspace_dir
                unless @root_dir
                    require "autoproj/workspace"
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

            def try_loading_installation_manifest
                Autoproj::InstallationManifest.from_workspace_root(@root_dir)
            rescue
            end

            PACKAGE_ROOT_PATH_RX = /^(srcdir|builddir|prefix):(.*)$/

            def resolve_package_root_path(package, manifest)
                if (m = PACKAGE_ROOT_PATH_RX.match(package))
                    kind = m[1]
                    name = m[2]
                else
                    kind = "srcdir"
                    name = package
                end

                unless (pkg = manifest.find_package_by_name(name))
                    raise ArgumentError, "no package #{name} in this workspace"
                end

                unless (dir = pkg.send(kind))
                    raise CLIInvalidArguments, "package #{pkg.name} has no #{kind}"
                end

                dir
            end

            def run(
                cmd, *args,
                use_cached_env: Ops.watch_running?(@root_dir),
                interactive: nil,
                package: nil, chdir: nil
            )
                env = load_cached_env if use_cached_env
                manifest = try_loading_installation_manifest if use_cached_env

                if !env || (package && !manifest)
                    require "autoproj"
                    require "autoproj/cli/inspection_tool"
                    ws = Workspace.from_dir(@root_dir)
                    ws.config.interactive = interactive unless interactive.nil?
                    loader = InspectionTool.new(ws)
                    loader.initialize_and_load(read_only: true)
                    loader.finalize_setup(read_only: true)
                    env = ws.full_env.resolved_env
                    manifest = ws.installation_manifest if package
                end

                root_path = resolve_package_root_path(package, manifest) if package
                chdir ||= root_path
                if chdir
                    chdir = File.expand_path(chdir, root_path)
                    chdir_kw = { chdir: chdir }
                end

                path = env["PATH"].split(File::PATH_SEPARATOR)
                program =
                    begin Ops.which(cmd, path_entries: [chdir, *path].compact)
                    rescue ::Exception => e
                        require "autoproj"
                        raise CLIInvalidArguments, e.message, e.backtrace
                    end

                begin
                    ::Process.exec(env, program, *args, **(chdir_kw || {}))
                rescue ::Exception => e
                    require "autoproj"
                    raise CLIInvalidArguments, e.message, e.backtrace
                end
            end
        end
    end
end
