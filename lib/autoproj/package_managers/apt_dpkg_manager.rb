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

            def self.parse_package_status(installed_packages, installed_versions, paragraph)
                if paragraph =~ /^Status: install ok installed$/
                    if paragraph =~ /^Package: (.*)$/
                        package_name = $1
                        installed_packages << package_name
                        if paragraph =~ /^Version: (.*)$/
                            installed_versions[package_name] = $1
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
                    package_name, version = AptDpkgManager.parse_apt_cache_paragraph(paragraph)
                    packages_versions[package_name] = version
                end
                package_name, version = AptDpkgManager.parse_apt_cache_paragraph("Package: #{apt_cache_show.rest}")
                packages_versions[package_name] = version
                packages_versions
            end

            LESS = -1
            EQUAL = 0
            GREATER = 1

            # Reference: https://www.debian.org/doc/debian-policy/ch-controlfields.html#version
            def split_package_version(version)
                epoch = '0'
                debian_revision = '0'

                upstream_version = version.split(':')
                if upstream_version.size > 1
                    epoch = upstream_version.first
                    upstream_version = upstream_version[1..-1].join(':')
                else
                    upstream_version = upstream_version.first
                end

                upstream_version = upstream_version.split('-')
                if upstream_version.size > 1
                    debian_revision = upstream_version.last
                    upstream_version = upstream_version[0..-2].join('-')
                else
                    upstream_version = upstream_version.first
                end

                [epoch, upstream_version, debian_revision]
            end

            def alpha?(look_ahead)
                look_ahead =~ /[[:alpha:]]/
            end

            def digit?(look_ahead)
                look_ahead =~ /[[:digit:]]/
            end

            def order(c)
                if digit?(c)
                    return 0
                elsif alpha?(c)
                    return c.ord
                elsif c == '~'
                    return -1
                elsif c
                    return c.ord + 256
                else
                    return 0
                end
            end

            # Ported from https://github.com/Debian/apt/blob/master/apt-pkg/deb/debversion.cc
            def compare_fragment(a, b)
                i = 0
                j = 0
                while i != a.size && j != b.size
                    first_diff = 0
                    while i != a.size && j != b.size && (!digit?(a[i]) || !digit?(b[j]))
                        vc = order(a[i])
                        rc = order(b[j])
                        return vc-rc if vc != rc
                        i += 1
                        j += 1
                    end

                    i += 1 while a[i] == '0'
                    j += 1 while b[j] == '0'

                    while digit?(a[i]) && digit?(b[j])
                        first_diff = a[i].ord - b[j].ord if first_diff == 0
                        i += 1
                        j += 1
                    end

                    return 1 if digit?(a[i])
                    return -1 if digit?(b[j])
                    return first_diff if first_diff != 0
                end

                return 0 if i == a.size && j == b.size

                if i == a.size
                    return 1 if b[j] == '~'
                    return -1
                end

                if j == b.size
                    return -1 if a[i] == '~'
                    return 1
                end
            end

            def normalize_comparison_result(result)
                return LESS if result < 0
                return GREATER if result > 0
                EQUAL
            end

            def compare_version(a, b)
                a_split = split_package_version(a)
                b_split = split_package_version(b)

                [0, 1].each do |i|
                    comp = normalize_comparison_result(compare_fragment(a_split[i], b_split[i]))
                    return comp if comp != EQUAL
                end
                normalize_comparison_result(compare_fragment(a_split[2], b_split[2]))
            end

            def updated?(package, available_version)
                # Consider up-to-date if the package is provided by another package (purely virtual)
                # Ideally, we should check the version of the package that provides it
                return true unless available_version && @installed_versions[package]

                compare_version(available_version, @installed_versions[package]) != GREATER
            end

            # On a dpkg-enabled system, checks if the provided package is installed
            # and returns true if it is the case
            def installed?(package_name, filter_uptodate_packages: false, install_only: false)
                @installed_packages, @installed_versions = AptDpkgManager.parse_dpkg_status(status_file) unless @installed_packages && @installed_versions
                if package_name =~ /^(\w[a-z0-9+-.]+)/
                    @installed_packages.include?($1)
                else
                    Autoproj.warn "#{package_name} is not a valid Debian package name"
                    false
                end
            end

            def install(packages, filter_uptodate_packages: false, install_only: false)
                packages_versions = AptDpkgManager.parse_packages_versions(packages)
                if filter_uptodate_packages || install_only
                    packages = packages.find_all do |package_name|
                        !installed?(package_name) || !updated?(package_name, packages_versions[package_name])
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

