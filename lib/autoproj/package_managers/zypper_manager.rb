module Autoproj
    module PackageManagers
        #Package manger for OpenSuse and Suse (untested)
        class ZypperManager < ShellScriptManager
            def initialize
                super(['zypper'], true,
                        "zypper install '%s'",
                        "zypper -n install '%s'")
            end

            def filter_uptodate_packages(packages, options = Hash.new)
                result = `LANG=C rpm -q --whatprovides '#{packages.join("' '")}'`
                has_all_pkgs = $?.success?

                if !has_all_pkgs
                    return packages # let zypper filter, we need root now anyways
                else 
                    return []
                end
            end

            def install(packages)
                patterns, packages = packages.partition { |pkg| pkg =~ /^@/ }
                patterns = patterns.map { |str| str[1..-1] }
                result = false
                if !patterns.empty?
                    result |= super(patterns,
                                    :auto_install_cmd => "zypper --non-interactive install --type pattern '%s'",
                                    :user_install_cmd => "zypper install --type pattern '%s'")
                end
                if !packages.empty?
                    result |= super(packages)
                end
                if result
                    # Invalidate caching of installed packages, as we just
                    # installed new packages !
                    @installed_packages = nil
                end
            end
        end
    end
end

