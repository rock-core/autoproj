module Autoproj
    module PackageManagers
	# Package manager interface for systems that use pkg (i.e. FreeBSD) as
        # their package manager
        class PkgManager < ShellScriptManager
            def initialize
                super(['pkg'], true,
                        "pkg install -y '%s'",
                        "pkg install -y '%s'")
            end
        end
    end
end

