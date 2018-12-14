require 'autoproj/package_managers/debian_version'

module Autoproj
    module PackageManagers
        # Package manager interface for systems that use APT and dpkg for
        # package management
        class AptDpkgManager < ShellScriptManager
            attr_accessor :status_file

            def initialize(ws, status_file = "/var/lib/dpkg/status")
                @status_file = status_file
                @installed_packages = nil
                @installed_versions = nil
                super(ws, true,
                      %w{apt-get install},
                      %w{DEBIAN_FRONTEND=noninteractive apt-get install -y})
            end

            def configure_manager
                super
                ws.config.declare 'apt_dpkg_update', 'boolean',
                    default: 'yes',
                    doc: ['Would you like autoproj to keep apt packages up-to-date?']
                keep_uptodate?
            end

            def keep_uptodate?
                ws.config.get('apt_dpkg_update')
            end

            def keep_uptodate=(flag)
                ws.config.set('apt_dpkg_update', flag, true)
            end

            def self.parse_package_status(installed_packages, installed_versions, paragraph)
                if paragraph =~ /^Status: install ok installed$/
                    if paragraph =~ /^Package: (.*)$/
                        package_name = $1
                        installed_packages << package_name
                        if paragraph =~ /^Version: (.*)$/
                            installed_versions[package_name] = DebianVersion.new($1)
                        end
                    end
                    if paragraph =~ /^Provides: (.*)$/
                        installed_packages.merge($1.split(',').map(&:strip))
                    end
                end
            end

            def self.parse_dpkg_status(status_file)
                installed_packages = Set.new
                installed_versions = {}
                dpkg_status = File.read(status_file)
                dpkg_status << "\n"

                dpkg_status = StringScanner.new(dpkg_status)
                if !dpkg_status.scan(/Package: /)
                    raise ArgumentError, "expected #{status_file} to have Package: lines but found none"
                end

                while paragraph_end = dpkg_status.scan_until(/Package: /)
                    paragraph = "Package: #{paragraph_end[0..-10]}"
                    parse_package_status(installed_packages, installed_versions, paragraph)
                end
                parse_package_status(installed_packages, installed_versions, "Package: #{dpkg_status.rest}")
                [installed_packages, installed_versions]
            end

            def self.parse_apt_cache_paragraph(paragraph)
                version = '0'
                if paragraph =~ /^Package: (.*)$/
                    package_name = $1
                    if paragraph =~ /^Version: (.*)$/
                        version = $1
                    end
                end
                [package_name, version]
            end

            def self.parse_packages_versions(packages)
                packages_versions = {}
                apt_cache_show = `apt-cache show --no-all-versions #{packages.join(' ')}`
                apt_cache_show = StringScanner.new(apt_cache_show)
                if !apt_cache_show.scan(/Package: /)
                    return packages_versions
                end

                while paragraph_end = apt_cache_show.scan_until(/Package: /)
                    paragraph = "Package: #{paragraph_end[0..-10]}"
                    package_name, version = parse_apt_cache_paragraph(paragraph)
                    packages_versions[package_name] = DebianVersion.new(version)
                end
                package_name, version = parse_apt_cache_paragraph("Package: #{apt_cache_show.rest}")
                packages_versions[package_name] = DebianVersion.new(version)
                packages_versions
            end

            def updated?(package, available_version)
                # Consider up-to-date if the package is provided by another package (purely virtual)
                # Ideally, we should check the version of the package that provides it
                return true unless available_version && @installed_versions[package]

                (available_version <= @installed_versions[package])
            end

            # On a dpkg-enabled system, checks if the provided package is installed
            # and returns true if it is the case
            def installed?(package_name, filter_uptodate_packages: false, install_only: false)
                @installed_packages, @installed_versions = self.class.parse_dpkg_status(status_file) unless @installed_packages && @installed_versions
                if package_name =~ /^(\w[a-z0-9+-.]+)/
                    @installed_packages.include?($1)
                else
                    Autoproj.warn "#{package_name} is not a valid Debian package name"
                    false
                end
            end

            def install(packages, filter_uptodate_packages: false, install_only: false)
                packages_versions = self.class.parse_packages_versions(packages)
                if filter_uptodate_packages || install_only
                    packages = packages.find_all do |package_name|
                        !installed?(package_name) || (keep_uptodate? && !updated?(package_name, packages_versions[package_name]))
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
