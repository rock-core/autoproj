module Autoproj
    module PackageManagers
        # Package manager interface for systems that use port (i.e. MacPorts/Darwin) as
        # their package manager
        class PortManager < ShellScriptManager
            def initialize(ws)
                super(ws, true,
                        %w{port install},
                        %w{port install})
            end
        end
    end
end

