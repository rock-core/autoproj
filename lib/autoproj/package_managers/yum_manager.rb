module Autoproj
    module PackageManagers
        # Package manager interface for systems that use yum
        class YumManager < ShellScriptManager
            def initialize(ws)
                super(ws, true,
                      %w[yum install],
                      %w[yum install -y])
            end

            def filter_uptodate_packages(packages)
                result = `LANG=C rpm -q --queryformat "%{NAME}\n" '#{packages.join("' '")}'`

                installed_packages = []
                new_packages = []
                result.split("\n").each_with_index do |line, index|
                    line = line.strip
                    if line =~ /package (.*) is not installed/
                        package_name = $1
                        unless packages.include?(package_name) # something is wrong, fallback to installing everything
                            return packages
                        end

                        new_packages << package_name
                    else
                        package_name = line.strip
                        unless packages.include?(package_name) # something is wrong, fallback to installing everything
                            return packages
                        end

                        installed_packages << package_name
                    end
                end
                new_packages
            end

            def install(packages, filter_uptodate_packages: false, install_only: false)
                packages = filter_uptodate_packages(packages) if filter_uptodate_packages

                patterns, packages = packages.partition { |pkg| pkg =~ /^@/ }
                patterns = patterns.map { |str| str[1..-1] }
                result = false
                unless patterns.empty?
                    result |= super(patterns,
                                    auto_install_cmd: %w[yum groupinstall -y],
                                    user_install_cmd: %w[yum groupinstall])
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
