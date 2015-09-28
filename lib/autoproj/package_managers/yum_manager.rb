module Autoproj
    module PackageManagers
        # Package manager interface for systems that use yum
        class YumManager < ShellScriptManager
            def initialize
                super(['yum'], true,
                      "yum install '%s'",
                      "yum install -y '%s'")
            end

            def filter_uptodate_packages(packages, options = Hash.new)
                result = `LANG=C rpm -q --queryformat "%{NAME}\n" '#{packages.join("' '")}'`

                installed_packages = []
                new_packages = []
                result.split("\n").each_with_index do |line, index|
                    line = line.strip
                    if line =~ /package (.*) is not installed/
                        package_name = $1
                        if !packages.include?(package_name) # something is wrong, fallback to installing everything
                            return packages
                        end
                        new_packages << package_name
                    else 
                        package_name = line.strip
                        if !packages.include?(package_name) # something is wrong, fallback to installing everything
                            return packages
                        end
                        installed_packages << package_name
                    end
                end
                new_packages
            end

            def install(packages)
                patterns, packages = packages.partition { |pkg| pkg =~ /^@/ }
                patterns = patterns.map { |str| str[1..-1] }
                result = false
                if !patterns.empty?
                    result |= super(patterns,
                                    :auto_install_cmd => "yum groupinstall -y '%s'",
                                    :user_install_cmd => "yum groupinstall '%s'")
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

