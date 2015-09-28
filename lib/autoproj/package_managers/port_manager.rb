module Autoproj
    module PackageManagers
        # Package manager interface for systems that use port (i.e. MacPorts/Darwin) as
        # their package manager
        class PortManager < ShellScriptManager
            def initialize
                super(['macports'], true,
                        "port install '%s'",
                        "port install '%s'")
            end
        end
    end
end

