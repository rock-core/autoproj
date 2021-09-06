module Autoproj
    module PackageManagers
        # Package manager interface for systems that use pkg (i.e. FreeBSD) as
        # their package manager
        class PkgManager < ShellScriptManager
            def initialize(ws)
                super(ws, true,
                        %w{pkg install -y},
                        %w{pkg install -y})
            end
        end
    end
end
