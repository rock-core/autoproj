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
        AUTOPROJ_OSDEPS = File.join(File.expand_path(File.dirname(__FILE__)), 'default.osdeps')
        def self.load_default
            OSDependencies.load(AUTOPROJ_OSDEPS)
        end

        attr_reader :definitions
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
                @operating_system = data
            else
                # Need to do some heuristics unfortunately
                @operating_system =
                    if File.exists?('/etc/debian_version')
                        codename = File.read('/etc/debian_version').chomp
                        ['debian', [codename]]
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
            distributor = `lsb_release -i -s`
            return unless $?.success?
            distributor = distributor.chomp
            codename    = `lsb_release -c -s`.chomp
            version     = `lsb_release -r -s`.chomp

            return [distributor, [codename, version]]
        end


        GAIN_ROOT_ACCESS = <<-EOSCRIPT
        if test `id -u` != "0"; then
            exec sudo /bin/bash $0 "$@"
        
        fi
        EOSCRIPT

        OS_PACKAGE_INSTALL = {
            'debian' => 'apt-get install -y %s',
            'ubuntu' => 'apt-get install -y %s'
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
                if data.kind_of?(Hash)
                    version_entry = data.find do |version_list, data|
                        version_list.to_s.split(',').
                            map(&:downcase).
                            any? { |v| os_version.include?(v) }
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

        def partition_packages(package_set)
            package_set = package_set.to_set
            osdeps, gems = [], []
            package_set.to_set.each do |name|
                pkg_def = definitions[name]
                if !pkg_def
                    raise ConfigError, "I know nothing about a prepackaged '#{name}' software"
                end

                if pkg_def.respond_to?(:to_str)
                    case(pkg_def.to_str)
                    when "gem" then
                        gems << name
                    else
                        raise ConfigError, "unknown OS-independent package management type #{pkg_def}"
                    end
                else
                    osdeps << name
                end
            end
            return osdeps, gems
        end

        def install(packages)
            osdeps, gems = partition_packages(packages)

            # Ideally, we would feed the OS dependencies to rosdep.
            # Unfortunately, this is C++ code and I don't want to install the
            # whole ROS stack just for rosdep ...
            #
            # So, for now, reimplement rosdep by ourselves. Given how things
            # are done, this is actually not so hard.
            shell_script = generate_os_script(osdeps)
            if Autoproj.verbose
                STDERR.puts "Installing non-ruby OS dependencies with"
                STDERR.puts shell_script
            end

            File.open('osdeps.sh', 'w') do |file|
                file.write shell_script
            end
            begin
                Autobuild::Subprocess.run 'autoproj', 'osdeps', 'bash', './osdeps.sh'
            ensure
                FileUtils.rm_f 'osdeps.sh'
            end

            # Don't install gems that are already there ...
            gems.delete_if do |name|
                version_requirements = Gem::Requirement.default
                available = Gem.source_index.find_name(name, version_requirements)
                !available.empty?
            end

            # Now install what is left
            if !gems.empty?
                if Autoproj.verbose
                    STDERR.puts "Installing rubygems dependencies with"
                    STDERR.puts "gem install #{gems.join(" ")}"
                end
                Autobuild::Subprocess.run 'autoproj', 'osdeps', 'gem', 'install', *gems
            end
        end
    end
end

