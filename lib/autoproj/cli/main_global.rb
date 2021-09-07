module Autoproj
    module CLI
        class MainGlobal < Thor
            namespace 'global'

            WorkspaceDir = Struct.new :name, :path, :present

            no_commands do
                def gather_workspaces_dirs(ws)
                    ws.each_with_object({}) do |w, h|
                        w_dirs = %w[root_dir prefix_dir build_dir].map do |name|
                            dir = w.public_send(name)
                            if dir.start_with?('/')
                                WorkspaceDir.new(name, dir, File.directory?(dir))
                            end
                        end.compact

                        h[w] = w_dirs
                    end
                end

                def filter_removed_workspaces(dirs)
                    dirs.delete_if do |w, w_dirs|
                        w_dirs.none? { |d| d.present }
                    end
                end
            end

            desc 'register', 'register the current workspace'
            def register
                require 'autoproj'
                ws = Workspace.default
                ws.load_config
                ws.register_workspace
            end

            desc 'status', 'display information about the known workspaces'
            def status
                require 'autoproj'
                ws = Workspace.registered_workspaces
                fields = Workspace::RegisteredWorkspace.members.map(&:to_s)

                dirs = gather_workspaces_dirs(ws)
                filter_removed_workspaces(dirs)
                Workspace.save_registered_workspaces(dirs.keys)

                format_w = fields.map(&:length).max + 1
                format = "%-#{format_w}s %s (%s)"
                blocks = dirs.map do |w, w_dirs|
                    lines = w_dirs.map do |d|
                        status =
                            if d.present
                                Autobuild.color('present', :green)
                            else
                                Autobuild.color('absent', :yellow)
                            end

                        format(format, "#{d.name}:", d.path, status)
                    end
                    lines.join("\n")
                end
                puts blocks.join("\n---\n")
            end
        end
    end
end
