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
                      "apt-get install '%s'",
                      "export DEBIAN_FRONTEND=noninteractive; apt-get install -y '%s'")
            end

            # On a dpkg-enabled system, checks if the provided package is installed
            # and returns true if it is the case
            def installed?(package_name, filter_uptodate_packages: false, install_only: false)
                if !@installed_packages
                    @installed_packages = Set.new
                    dpkg_status = File.readlines(status_file)
                    dpkg_status << ""

                    current_packages = []
                    is_installed = false
                    dpkg_status.each do |line|
                        line = line.chomp
                        line = line.encode( "UTF-8", "binary", :invalid => :replace, :undef => :replace)
                        if line == ""
                            if is_installed
                                current_packages.each do |pkg|
                                    @installed_packages << pkg
                                end
                                is_installed = false
                            end
                            current_packages.clear
                        elsif line =~ /Package: (.*)$/
                            current_packages << $1
                        elsif line =~ /Provides: (.*)$/
                            current_packages.concat($1.split(',').map(&:strip))
                        elsif line == "Status: install ok installed"
                            is_installed = true
                        end
                    end
                end
                
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

