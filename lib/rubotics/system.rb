module Rubotics
    BASE_DIR     = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))
    PACKAGES_DIR = File.join(BASE_DIR, 'packages')

    class NotOnDebian < RuntimeError; end

    # Returns the version of APT, or raises RuntimeError if APT is not there
    def self.apt_version
        policy = `apt-cache policy apt`
        if !policy
            raise NotOnDebian, "error running apt-cache, are you on a Debian system ?"
        end

        version_line = policy.split("\n").grep(/Installed:/)
        if version_line.empty?
            raise RuntimeError, "cannot find APT version"
        end

        if version_line[0] =~ /Installed:\s+(\d+)\.(\d+)\.(\d+)/
            [$1, $2, $3].map(&:to_i)
        else
            raise RuntimeError, "cannot parse version line #{version_line[0]}"
        end
    end

    # Returns true if on a Debian-compatible system, and false otherwise
    def self.on_debian?
        apt_version
        true
    rescue NotOnDebian
        false
    end

    # Installs the Debian packages by adding a rubotics.sources files in
    # /etc/apt/sources.list.d (if not already present), running apt-get update
    # and install the relevant packages
    def self.install_debian_profile(profile_name, install_mode = 'install')
        # Check the version of APT. We need support for sources.list.d, so apt
        # needs to be >= 0.6.43
        apt_version = self.apt_version
        if apt_version < [0, 6, 43]
            raise RuntimeError, "a version of APT greater than 0.6.43 is required"
        end

        # Check if rubotics.list is in /etc/apt/sources.list.d, and install it
        # if needed. Run apt-get update only if the source was not there before
        #
        # Also, check that the rubotics.list "thing" in sources.list.d is
        # actually a symlink to our own copy
        source_list_d    = File.join('etc', 'apt', 'sources.list.d')
        installed_source = File.join(sources_list_d, 'rubotics.list')
        do_delete = if File.exists?(installed_source)
                        if !File.symlink?(installed_source)
                            # Not a symlink, upgrade
                            true
                        else
                            # Check that it is pointing to our rubotics installation
                            actual = File.readlink(installed_source)
                            target = File.join(PACKAGES_DIR, "rubotics.list")
                            actual != target
                        end
                    end
        if do_delete
            run_as_root "rm", "-f", installed_source
        end

        if !File.exists?(File.join(sources_list_d, 'rubotics.list'))
            File.open( File.join(PACKAGES_DIR, "rubotics.list"), "w" ) do |io|
                io << File.read(File.join(PACKAGES_DIR, "rubotics.list.in"))
                io << "\ndeb file://#{PACKAGES_DIR} ./\n"
            end
            run_as_root "ln", "-s", File.join(PACKAGES_DIR, 'rubotics.list'), sources_list_d
            run_as_root 'apt-get', 'update'
        end

        # Now, finally install the debian packages. This will upgrade if needed
        run_as_root 'apt-get', install_mode, '-y', "rubotics-#{profile}"
    end

    # Install the required rubotics profile gem
    def self.install_gem_profile(profile_name)
        run_as_user 'gem', 'install', "-y", File.join(PACKAGES_DIR, "rubotics-#{profile_name}")
    end

    def self.run_as_user(*args)
        if !system(*args)
            raise "failed to run #{args.join(" ")}"
        end
    end

    def self.run_as_root(*args)
        if !system('sudo', *args)
            raise "failed to run #{args.join(" ")} as root"
        end
    end
end

