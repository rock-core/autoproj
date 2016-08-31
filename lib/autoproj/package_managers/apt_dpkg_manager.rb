module Autoproj
    module PackageManagers
        # Package manager interface for systems that use APT and dpkg for
        # package management
        class AptDpkgManager < ShellScriptManager
            attr_accessor :status_file

            def initialize(ws, status_file = "/var/lib/dpkg/status")
                @status_file = status_file
                @installed_packages = nil
                super(ws, true,
                      %w{apt-get install},
                      %w{DEBIAN_FRONTEND=noninteractive apt-get install -y})
            end

            def self.parse_package_status(installed_packages, paragraph)
                if paragraph =~ /^Status: install ok installed$/
                    if paragraph =~ /^Package: (.*)$/
                        installed_packages << $1
                    end
                    if paragraph =~ /^Provides: (.*)$/
                        installed_packages.merge($1.split(',').map(&:strip))
                    end
                end
            end

            def self.parse_dpkg_status(status_file)
                installed_packages = Set.new
                dpkg_status = File.read(status_file)
                dpkg_status << "\n"

                dpkg_status = StringScanner.new(dpkg_status)
                if !dpkg_status.scan(/Package: /)
                    raise ArgumentError, "expected #{status_file} to have Package: lines but found none"
                end

                while paragraph_end = dpkg_status.scan_until(/Package: /)
                    paragraph = "Package: #{paragraph_end[0..-10]}"
                    parse_package_status(installed_packages, paragraph)
                end
                parse_package_status(installed_packages, "Package: #{dpkg_status.rest}")
                installed_packages
            end

            # On a dpkg-enabled system, checks if the provided package is installed
            # and returns true if it is the case
            def installed?(package_name, filter_uptodate_packages: false, install_only: false)
                @installed_packages ||= AptDpkgManager.parse_dpkg_status(status_file)
                
                if package_name =~ /^(\w[a-z0-9+-.]+)/
                    @installed_packages.include?($1)
                else
                    Autoproj.warn "#{package_name} is not a valid Debian package name"
                    false
                end
            end
            
            def install(packages, filter_uptodate_packages: false, install_only: false)
                if filter_uptodate_packages || install_only
                    packages = packages.find_all do |package_name|
                        !installed?(package_name)
                    end
                end

                if super(packages)
                    # Invalidate caching of installed packages, as we just
                    # installed new packages !
                    @installed_packages = nil
                end
            end
        end
    end
end

