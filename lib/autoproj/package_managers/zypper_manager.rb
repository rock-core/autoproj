module Autoproj
    module PackageManagers
        # Package manger for OpenSuse and Suse (untested)
        class ZypperManager < ShellScriptManager
            def initialize(ws)
                super(ws, true,
                        %w[zypper install],
                        %w[zypper -n install])
            end

            def filter_uptodate_packages(packages)
                `LANG=C rpm -q --whatprovides '#{packages.join("' '")}'`
                has_all_pkgs = $?.success?

                if !has_all_pkgs
                    packages # let zypper filter, we need root now anyways
                else
                    []
                end
            end

            def install(packages, filter_uptodate_packages: false, install_only: false)
                if filter_uptodate_packages || install_only
                    packages = filter_uptodate_packages(packages)
                end

                patterns, packages = packages.partition { |pkg| pkg =~ /^@/ }
                patterns = patterns.map { |str| str[1..-1] }
                result = false
                unless patterns.empty?
                    result |= super(patterns,
                                    auto_install_cmd: %w[zypper --non-interactive install --type pattern],
                                    user_install_cmd: %w[zypper install --type pattern])
                end
                result |= super(packages) unless packages.empty?
                if result
                    # Invalidate caching of installed packages, as we just
                    # installed new packages !
                    @installed_packages = nil
                end
            end
        end
    end
end
