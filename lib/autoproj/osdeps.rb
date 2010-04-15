require 'tempfile'
module Autoproj
    class OSDependencies
        def self.load(file)
            data =
                begin
                    YAML.load(File.read(file))
                rescue ArgumentError => e
                    raise ConfigError, "error in #{file}: #{e.message}"
                end

            OSDependencies.new(data)
        end

        class << self
            attr_reader :aliases
        end
        @aliases = Hash.new

        def self.alias(old_name, new_name)
            @aliases[new_name] = old_name
        end

        def self.autodetect_ruby
            ruby_package =
                if RUBY_VERSION < "1.9.0" then "ruby18"
                else "ruby19"
                end
            self.alias(ruby_package, "ruby")
        end

        AUTOPROJ_OSDEPS = File.join(File.expand_path(File.dirname(__FILE__)), 'default.osdeps')
        def self.load_default
            @default_osdeps ||= OSDependencies.load(AUTOPROJ_OSDEPS)
        end

        attr_reader :definitions
        def gem_fetcher
            @gem_fetcher ||= Gem::SpecFetcher.fetcher
        end

        def initialize(defs = Hash.new)
            @definitions = defs.to_hash
        end

        def merge(info)
            @definitions = definitions.merge(info.definitions)
        end

        def operating_system
            if @operating_system
                return @operating_system
            elsif data = os_from_lsb
                if data[0] != "debian"
                    # Fall back to reading debian_version, as
                    # sid is listed as lenny by lsb-release
                    @operating_system = data
                end
            end

            if !@operating_system
                # Need to do some heuristics unfortunately
                @operating_system =
                    if File.exists?('/etc/debian_version')
                        codename = File.read('/etc/debian_version').strip
                        ['debian', [codename]]
                    elsif File.exists?('/etc/gentoo-release')
                        release_string = File.read('/etc/gentoo-release').strip
                        release_string =~ /^.*([^\s]+)$/
                            version = $1
                        ['gentoo', [version]]
                    elsif File.exists?('/etc/arch-release')
                        codename = "Unknown"
                        puts "Found Arch"
                        ['arch', [codename]]
                    else
                        raise ConfigError, "Unknown operating system"
                    end
            end

            # Normalize the names to lowercase
            @operating_system =
                [@operating_system[0].downcase,
                 @operating_system[1].map(&:downcase)]
        end

        def os_from_lsb
            has_lsb_release = `which lsb_release`
            return unless $?.success?

            distributor = `lsb_release -i -s`
            distributor = distributor.strip.downcase
            codename    = `lsb_release -c -s`.strip.downcase
            version     = `lsb_release -r -s`.strip.downcase

            return [distributor, [codename, version]]
        end


        GAIN_ROOT_ACCESS = <<-EOSCRIPT
        if test `id -u` != "0"; then
            exec sudo /bin/bash $0 "$@"
        
        fi
        EOSCRIPT

        OS_PACKAGE_INSTALL = {
            'debian' => 'apt-get install -y %s',
            'ubuntu' => 'apt-get install -y %s',
            'gentoo' => 'emerge --noreplace %s',
            'arch' => 'pacman -Sy --noconfirm %s'
        }

        def generate_os_script(dependencies)
            os_name, os_version = operating_system
            if !OS_PACKAGE_INSTALL.has_key?(os_name)
                raise ConfigError, "I don't know how to install packages on #{os_name}"
            end

            shell_snippets = ""
            os_packages    = []
            dependencies.each do |name|
                dep_def = definitions[name]
                if !dep_def
                    raise ConfigError, "I don't know how to install '#{name}'"
                end

                # Find a matching entry for the OS name
                os_entry = dep_def.find do |name_list, data|
                    name_list.split(',').
                        map(&:downcase).
                        any? { |n| n == os_name }
                end

                if !os_entry
                    raise ConfigError, "I don't know how to install '#{name}' on #{os_name}"
                end

                data = os_entry.last
                # This package does not need to be installed on this operating system (example: build tools on Gentoo)
                next if !data || data == "ignore"

                if data.kind_of?(Hash)
                    version_entry = data.find do |version_list, data|
                        version_list.to_s.split(',').
                            map(&:downcase).
                            any? do |v|
                                os_version.any? { |osv| Regexp.new(v) =~ osv }
                            end
                    end

                    if !version_entry
                        raise ConfigError, "I don't know how to install '#{name}' on this specific version of #{os_name} (#{os_version.join(", ")})"
                    end
                    data = version_entry.last
                end

                if data.respond_to?(:to_ary)
                    os_packages.concat data.to_ary
                elsif data.to_str =~ /\w+/
                    os_packages << data.to_str
                else
                    shell_snippets << "\n" << data << "\n"
                end
            end

            "#! /bin/bash\n" +
            GAIN_ROOT_ACCESS + "\n" +
                (OS_PACKAGE_INSTALL[os_name] % [os_packages.join(" ")]) +
                "\n" + shell_snippets
        end

        # call-seq:
        #   partition_packages(package_names) => os_packages, gem_packages
        def partition_packages(package_set, package_osdeps = Hash.new)
            package_set = package_set.
                map { |name| OSDependencies.aliases[name] || name }.
                to_set

            osdeps, gems = [], []
            package_set.to_set.each do |name|
                pkg_def = definitions[name]
                if !pkg_def
                    msg = "I know nothing about a prepackaged software called '#{name}'"
                    if pkg_names = package_osdeps[name]
                        msg += ", it is listed as dependency of the following package(s): #{pkg_names.join(", ")}"
                    end

                    raise ConfigError, msg
                end

                pkg_def = pkg_def.dup

                if pkg_def.respond_to?(:to_str)
                    case(pkg_def.to_str)
                    when "ignore" then
                    when "gem" then
                        gems << name
                    else
                        raise ConfigError, "unknown OS-independent package management type #{pkg_def} for #{name}"
                    end
                else
                    pkg_def.delete_if do |distrib_name, defs|
                        if distrib_name == "gem"
                            gems.concat([*defs])
                            true
                        end
                    end
                    if !pkg_def.empty?
                        osdeps << name
                    end
                end
            end
            return osdeps, gems
        end

        def guess_gem_program
            if Autobuild.programs['gem']
                return Autobuild.programs['gem']
            end

            ruby_bin = Config::CONFIG['RUBY_INSTALL_NAME']
            if ruby_bin =~ /^ruby(.+)$/
                Autobuild.programs['gem'] = "gem#{$1}"
            else
                Autobuild.programs['gem'] = "gem"
            end
        end

        # Requests the installation of the given set of packages
        def install(packages, package_osdeps = Hash.new)
            osdeps, gems = partition_packages(packages, package_osdeps)

            did_something = false

            # Ideally, we would feed the OS dependencies to rosdep.
            # Unfortunately, this is C++ code and I don't want to install the
            # whole ROS stack just for rosdep ...
            #
            # So, for now, reimplement rosdep by ourselves. Given how things
            # are done, this is actually not so hard.
            if !osdeps.empty?
                shell_script = generate_os_script(osdeps)
                if Autoproj.verbose
                    STDERR.puts "Installing non-ruby OS dependencies with"
                    STDERR.puts shell_script
                end

                File.open('osdeps.sh', 'w') do |file|
                    file.write shell_script
                end
                Autobuild.progress "installing/updating OS dependencies: #{osdeps.join(", ")}"
                begin
                    Autobuild::Subprocess.run 'autoproj', 'osdeps', '/bin/bash', File.expand_path('osdeps.sh')
                ensure
                    FileUtils.rm_f 'osdeps.sh'
                end
                did_something ||= true
            end

            if !gems.empty?
                # Don't install gems that are already there ...
                gems.delete_if do |name|
                    version_requirements = Gem::Requirement.default
                    installed = Gem.source_index.find_name(name, version_requirements)
                    if !installed.empty? && Autobuild.do_update
                        # Look if we can update the package ...
                        dep = Gem::Dependency.new(name, version_requirements)
                        available = gem_fetcher.find_matching(dep)
                        installed_version = installed.map(&:version).max
                        available_version = available.map { |(name, v), source| v }.max
                        needs_update = (available_version > installed_version)
                        !needs_update
                    else
                        !installed.empty?
                    end
                end
            end

            # Now install what is left
            if !gems.empty?
                guess_gem_program

                if Autoproj.verbose
                    STDERR.puts "Installing rubygems dependencies with"
                    STDERR.puts "gem install #{gems.join(" ")}"
                end
                Autobuild.progress "installing/updating RubyGems dependencies: #{gems.join(", ")}"
                Autobuild::Subprocess.run 'autoproj', 'osdeps', Autobuild.tool('gem'), 'install', *gems
                did_something ||= true
            end

            did_something
        end
    end
end

