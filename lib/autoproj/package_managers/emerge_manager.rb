module Autoproj
    module PackageManagers
        # Package manager interface for systems that use emerge (i.e. gentoo) as
        # their package manager
        class EmergeManager < ShellScriptManager
            def initialize(ws)
                super(ws, true,
                        %w{emerge},
                        %w{emerge --noreplace})
            end
        end
    end
end

