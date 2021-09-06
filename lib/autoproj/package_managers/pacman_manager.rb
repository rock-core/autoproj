module Autoproj
    module PackageManagers
        # Package manager interface for systems that use pacman (i.e. arch) as
        # their package manager
        class PacmanManager < ShellScriptManager
            def initialize(ws)
                super(ws, true,
                        %w{pacman -Sy --needed},
                        %w{pacman -Sy --needed --noconfirm})
            end
        end
    end
end
