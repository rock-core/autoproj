module Autoproj
    module PackageManagers
        # Package manager interface for systems that use emerge (i.e. gentoo) as
        # their package manager
        class EmergeManager < ShellScriptManager
            def initialize
                super(['emerge'], true,
                        "emerge '%s'",
                        "emerge --noreplace '%s'")
            end
        end
    end
end

