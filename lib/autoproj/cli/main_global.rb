module Autoproj
    module CLI
        class MainGlobal < Thor
            namespace 'global'

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
                format_w = fields.map(&:length).max + 1
                format = "%-#{format_w}s %s (%s)"
                blocks = ws.map do |w|
                    %w[root_dir prefix_dir build_dir].map do |name|
                        dir = w.public_send(name)
                        if dir.start_with?('/')
                            status = if File.directory?(dir)
                                         Autobuild.color('present', :green)
                                     else
                                         Autobuild.color('absent', :yellow)
                                     end

                            format(format, "#{name}:", dir, status)
                        end
                    end.compact.join("\n")
                end
                puts blocks.join("---\n")
            end
        end
    end
end
