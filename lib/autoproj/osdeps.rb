require 'tempfile'
module Autoproj
    # Module that contains the package manager implementations for the
    # OSDependencies class
    module PackageManagers
        # Base class for all package managers. Subclasses must add the
        # #install(packages) method and may add the
        # #filter_uptodate_packages(packages) method
        class Manager
            attr_reader :names

            attr_writer :enabled
            def enabled?; !!@enabled end

            attr_writer :silent
            def silent?; !!@silent end

            def initialize(names = [])
                @names = names.dup
                @enabled = true
                @silent = true
            end

            def name
                names.first
            end
        end

        # Dummy package manager used for unknown OSes. It simply displays a
        # message to the user when packages are needed
        class UnknownOSManager < Manager
            def initialize
                super(['unknown'])
                @installed_osdeps = Set.new
            end

            def osdeps_interaction_unknown_os(osdeps)
                puts <<-EOMSG
  #{Autoproj.color("The build process requires some other software packages to be installed on our operating system", :bold)}
  #{Autoproj.color("If they are already installed, simply ignore this message", :red)}

    #{osdeps.to_a.sort.join("\n    ")}

                EOMSG
                print Autoproj.color("Press ENTER to continue", :bold)
                STDOUT.flush
                STDIN.readline
                puts
                nil
            end

            def install(osdeps)
                if silent?
                    return false
                else
                    osdeps = osdeps.to_set
                    osdeps -= @installed_osdeps
                    if !osdeps.empty?
                        result = osdeps_interaction_unknown_os(osdeps)
                    end
                    @installed_osdeps |= osdeps
                    return result
                end
            end
        end

        # Base class for all package managers that simply require the call of a
        # shell script to install packages (e.g. yum, apt, ...)
        class ShellScriptManager < Manager
            def self.execute_as_root(script, with_locking)
                if with_locking
                    File.open('/tmp/autoproj_osdeps_lock', 'w') do |lock_io|
                        begin
                            while !lock_io.flock(File::LOCK_EX | File::LOCK_NB)
                                Autoproj.message "  waiting for other autoproj instances to finish their osdeps installation"
                                sleep 5
                            end
                            return execute_as_root(script, false)
                        ensure
                            lock_io.flock(File::LOCK_UN)
                        end
                    end
                end


                Tempfile.open('osdeps_sh') do |io|
                    io.puts "#! /bin/bash"
                    io.puts GAIN_ROOT_ACCESS
                    io.write script
                    io.flush
                    Autobuild::Subprocess.run 'autoproj', 'osdeps', '/bin/bash', io.path
                end
            end

            GAIN_ROOT_ACCESS = <<-EOSCRIPT
# Gain root access using sudo
if test `id -u` != "0"; then
    exec sudo /bin/bash $0 "$@"

fi
            EOSCRIPT

            attr_writer :needs_locking
            def needs_locking?; !!@needs_locking end

            attr_reader :auto_install_cmd
            attr_reader :user_install_cmd

            def initialize(names, needs_locking, user_install_cmd, auto_install_cmd)
                super(names)
                @needs_locking, @user_install_cmd, @auto_install_cmd =
                    needs_locking, user_install_cmd, auto_install_cmd
            end

            def generate_user_os_script(os_packages)
                if user_install_cmd
                    (user_install_cmd % [os_packages.join("' '")])
                else generate_auto_os_script(os_packages)
                end
            end

            def generate_auto_os_script(os_packages)
                (auto_install_cmd % [os_packages.join("' '")])
            end

            def osdeps_interaction(os_packages, shell_script)
                if OSDependencies.force_osdeps
                    return true
                elsif enabled?
                    return true
                elsif silent?
                    return false
                end

                # We're asked to not install the OS packages but to display them
                # anyway, do so now
                puts <<-EOMSG

                #{Autoproj.color("The build process and/or the packages require some other software to be installed", :bold)}
                #{Autoproj.color("and you required autoproj to not install them itself", :bold)}
                #{Autoproj.color("\nIf these packages are already installed, simply ignore this message\n", :red) if !respond_to?(:filter_uptodate_packages)}
    The following packages are available as OS dependencies, i.e. as prebuilt
    packages provided by your distribution / operating system. You will have to
    install them manually if they are not already installed

                #{os_packages.sort.join("\n      ")}

    the following command line(s) can be run as root to install them:

                #{shell_script.split("\n").join("\n|   ")}

            EOMSG
                print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"
                STDOUT.flush
                STDIN.readline
                puts
                false
            end

            def install(packages)
                handled_os = OSDependencies.supported_operating_system?
                if handled_os
                    shell_script = generate_auto_os_script(packages)
                    user_shell_script = generate_user_os_script(packages)
                end
                if osdeps_interaction(packages, user_shell_script)
                    Autoproj.message "  installing OS packages: #{packages.sort.join(", ")}"

                    if Autoproj.verbose
                        Autoproj.message "Generating installation script for non-ruby OS dependencies"
                        Autoproj.message shell_script
                    end
                    ShellScriptManager.execute_as_root(shell_script, needs_locking?)
                    return true
                end
                false
            end
        end

        # Package manager interface for systems that use pacman (i.e. arch) as
        # their package manager
        class PacmanManager < ShellScriptManager
            def initialize
                super(['pacman'], true,
                        "pacman '%s'",
                        "pacman -Sy --noconfirm '%s'")
            end
        end

        # Package manager interface for systems that use emerge (i.e. gentoo) as
        # their package manager
        class EmergeManager < ShellScriptManager
            def initialize
                super(['emerge'], true,
                        "emerge '%s'",
                        "emerge --noreplace '%s'")
            end
        end

        # Package manager interface for systems that use yum
        class YumManager < ShellScriptManager
            def initialize
                super(['yum'], true,
                      "yum install '%s'",
                      "yum install -y '%s'")
            end

            def filter_uptodate_packages(packages)
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
        end

        # Package manager interface for systems that use APT and dpkg for
        # package management
        class AptDpkgManager < ShellScriptManager
            def initialize
                super(['apt-dpkg'], true,
                      "apt-get install '%s'",
                      "export DEBIAN_FRONTEND=noninteractive; apt-get install -y '%s'")
            end

            # On a dpkg-enabled system, checks if the provided package is installed
            # and returns true if it is the case
            def installed?(package_name)
                if !@installed_packages
                    @installed_packages = Set.new
                    dpkg_status = File.readlines('/var/lib/dpkg/status')

                    current_packages = []
                    is_installed = false
                    dpkg_status.each do |line|
                        line = line.chomp
                        if line == ""
                            if is_installed
                                current_packages.each do |pkg|
                                    @installed_packages << pkg
                                end
                                current_packages.clear
                                is_installed = false
                            end
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
            
            def install(packages)
                if super
                    # Invalidate caching of installed packages, as we just
                    # installed new packages !
                    @installed_packages = nil
                end
            end
            
            def filter_uptodate_packages(packages)
                packages.find_all do |package_name|
                    !installed?(package_name)
                end
            end
        end

        # Package manager interface for the RubyGems system
        class GemManager < Manager
            class << self
                attr_accessor :with_prerelease
                attr_accessor :with_doc
            end
            @with_prerelease = false
            @with_doc = false

            def initialize
                super(['gem'])
                @installed_gems = Set.new
            end

            # Used to override the Gem::SpecFetcher object used by this gem
            # manager. Useful mainly for testing
            attr_writer :gem_fetcher

            # The set of gems installed during this autoproj session
            attr_reader :installed_gems

            def gem_fetcher
                if !@gem_fetcher
                    Autoproj.message "  looking for RubyGems updates"
                    @gem_fetcher = Gem::SpecFetcher.fetcher
                end
                @gem_fetcher
            end

            def guess_gem_program
                if Autobuild.programs['gem']
                    return Autobuild.programs['gem']
                end

                ruby_bin = RbConfig::CONFIG['RUBY_INSTALL_NAME']
                if ruby_bin =~ /^ruby(.+)$/
                    Autobuild.programs['gem'] = "gem#{$1}"
                else
                    Autobuild.programs['gem'] = "gem"
                end
            end

            def install(gems)
                guess_gem_program

                base_cmdline = [Autobuild.tool('gem'), 'install']
                if !GemManager.with_doc
                    base_cmdline << '--no-rdoc' << '--no-ri'
                end

                if GemManager.with_prerelease
                    base_cmdline << "--prerelease"
                end
                with_version, without_version = gems.partition { |name, v| v }

                cmdlines = []
                if !without_version.empty?
                    cmdlines << (base_cmdline + without_version.flatten)
                end
                with_version.each do |name, v|
                    cmdlines << base_cmdline + [name, "-v", v]
                end

                if gems_interaction(gems, cmdlines)
                    Autoproj.message "  installing/updating RubyGems dependencies: #{gems.map { |g| g.join(" ") }.sort.join(", ")}"

                    cmdlines.each do |c|
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', *c
                    end
                    gems.each do |name, v|
                        installed_gems << name
                    end
                    did_something = true
                end
            end

            # Returns the set of RubyGem packages in +packages+ that are not already
            # installed, or that can be upgraded
            def filter_uptodate_packages(gems)
                # Don't install gems that are already there ...
                gems = gems.dup
                gems.delete_if do |name, version|
                    next(true) if installed_gems.include?(name)

                    version_requirements = Gem::Requirement.new(version || '>= 0')
                    installed =
                        if Gem::Specification.respond_to?(:find_by_name)
                            begin
                                [Gem::Specification.find_by_name(name, version_requirements)]
                            rescue Gem::LoadError
                                []
                            end
                        else
                            Gem.source_index.find_name(name, version_requirements)
                        end

                    if !installed.empty? && Autobuild.do_update
                        # Look if we can update the package ...
                        dep = Gem::Dependency.new(name, version_requirements)
                        available = gem_fetcher.find_matching(dep, true, true, GemManager.with_prerelease)
                        installed_version = installed.map(&:version).max
                        available_version = available.map { |(name, v), source| v }.max
                        if !available_version
                            if version
                                raise ConfigError.new, "cannot find any gem with the name '#{name}' and version #{version}"
                            else
                                raise ConfigError.new, "cannot find any gem with the name '#{name}'"
                            end
                        end
                        needs_update = (available_version > installed_version)
                        !needs_update
                    else
                        !installed.empty?
                    end
                end
                gems
            end

            def parse_package_entry(entry)
                if entry =~ /^([^><=~]*)([><=~]+.*)$/
                    [$1.strip, $2.strip]
                else
                    [entry]
                end
            end

            def gems_interaction(gems, cmdlines)
                if OSDependencies.force_osdeps
                    return true
                elsif enabled?
                    return true
                elsif silent?
                    return false
                end

                # We're not supposed to install rubygem packages but silent is not
                # set, so display information about them anyway
                puts <<-EOMSG
      #{Autoproj.color("The build process and/or the packages require some Ruby Gems to be installed", :bold)}
      #{Autoproj.color("and you required autoproj to not do it itself", :bold)}
        You can use the --all or --ruby options to autoproj osdeps to install these
        packages anyway, and/or change to the osdeps handling mode by running an
        autoproj operation with the --reconfigure option as for instance
        autoproj build --reconfigure
        
        The following command line can be used to install them manually
        
          #{cmdlines.map { |c| c.join(" ") }.join("\n      ")}
        
        Autoproj expects these Gems to be installed in #{Autoproj.gem_home} This can
        be overridden by setting the AUTOPROJ_GEM_HOME environment variable manually

                EOMSG
                print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"

                STDOUT.flush
                STDIN.readline
                puts
                false
            end
        end
    end

    # Manager for packages provided by external package managers
    class OSDependencies
	class << self
	    # When requested to load a file called X.Y, the osdeps code will
	    # also look for files called X-suffix.Y, where 'suffix' is an
	    # element in +osdeps_suffixes+
	    #
	    # A usage of this functionality is to make loading conditional to
	    # the available version of certain tools, namely Ruby. Autoproj for
	    # instance adds ruby18 when started on Ruby 1.8 and ruby19 when
	    # started on Ruby 1.9
	    attr_reader :suffixes
	end
	@suffixes = []

        def self.load(file)
	    if !File.file?(file)
		raise ArgumentError, "no such file or directory #{file}"
	    end

	    candidates = [file]
	    candidates.concat(suffixes.map { |s| "#{file}-#{s}" })

            error_t = if defined? Psych::SyntaxError then [ArgumentError, Psych::SyntaxError]
                      else ArgumentError
                      end

	    result = OSDependencies.new
	    candidates.each do |file|
                next if !File.file?(file)
                file = File.expand_path(file)
                begin
                    data = YAML.load(File.read(file)) || Hash.new
                    verify_definitions(data)
                rescue *error_t => e
                    raise ConfigError.new, "error in #{file}: #{e.message}", e.backtrace
                end

                result.merge(OSDependencies.new(data, file))
	    end
	    result
        end

        class << self
            attr_reader :aliases
            attr_accessor :force_osdeps
        end
        @aliases = Hash.new

        attr_writer :silent
        def silent?; @silent end

        def self.alias(old_name, new_name)
            @aliases[new_name] = old_name
        end

	def self.ruby_version_keyword
            if RUBY_VERSION < "1.9.0" then "ruby18"
            else "ruby19"
            end
        end

        def self.autodetect_ruby
            self.alias(ruby_version_keyword, "ruby")
        end
	self.suffixes << ruby_version_keyword
        autodetect_ruby

        AUTOPROJ_OSDEPS = File.join(File.expand_path(File.dirname(__FILE__)), 'default.osdeps')
        def self.load_default
            file = ENV['AUTOPROJ_DEFAULT_OSDEPS'] || AUTOPROJ_OSDEPS
            if !File.file?(file)
                Autoproj.warn "#{file} (from AUTOPROJ_DEFAULT_OSDEPS) is not a file, falling back to #{AUTOPROJ_OSDEPS}"
                file = AUTOPROJ_OSDEPS
            end
            OSDependencies.load(file)
        end

        PACKAGE_HANDLERS = [PackageManagers::AptDpkgManager,
            PackageManagers::GemManager,
            PackageManagers::EmergeManager,
            PackageManagers::PacmanManager,
            PackageManagers::YumManager]
        OS_PACKAGE_HANDLERS = {
            'debian' => 'apt-dpkg',
            'gentoo' => 'emerge',
            'arch' => 'pacman',
            'fedora' => 'yum'
        }

        # The information contained in the OSdeps files, as a hash
        attr_reader :definitions
        # All the information contained in all the OSdeps files, as a mapping
        # from the OSdeps package name to [osdeps_file, definition] pairs
        attr_reader :all_definitions
        # The information as to from which osdeps file the current package
        # information in +definitions+ originates. It is a mapping from the
        # package name to the osdeps file' full path
        attr_reader :sources

        # Use to override the autodetected OS-specific package handler
        attr_writer :os_package_handler

        # Returns the package manager object for the current OS
        def os_package_handler
            if @os_package_handler.nil?
                os_names, _ = OSDependencies.operating_system
                if os_names && (key = os_names.find { |name| OS_PACKAGE_HANDLERS[name] })
                    @os_package_handler = package_handlers[OS_PACKAGE_HANDLERS[key]]
                    if !@os_package_handler
                        raise ArgumentError, "found #{OS_PACKAGE_HANDLERS[name]} as the required package handler for #{os_names.join(", ")}, but it is not registered"
                    end
                else
                    @os_package_handler = PackageManagers::UnknownOSManager.new
                end
            end
            return @os_package_handler
        end

        # Returns the set of package managers
        def package_handlers
            if !@package_handlers
                @package_handlers = Hash.new
                PACKAGE_HANDLERS.each do |klass|
                    obj = klass.new
                    obj.names.each do |n|
                        @package_handlers[n] = obj
                    end
                end
            end
            @package_handlers
        end

        # The Gem::SpecFetcher object that should be used to query RubyGems, and
        # install RubyGems packages
        def initialize(defs = Hash.new, file = nil)
            @definitions = defs.to_hash
            @all_definitions = Hash.new { |h, k| h[k] = Array.new }

            @sources     = Hash.new
            @installed_packages = Set.new
            if file
                defs.each_key do |package_name|
                    sources[package_name] = file
                    all_definitions[package_name] << [[file], defs[package_name]]
                end
            end
            @silent = true
            @filter_uptodate_packages = true
        end

        # Returns the full path to the osdeps file from which the package
        # definition for +package_name+ has been taken
        def source_of(package_name)
            sources[package_name]
        end

        # Merges the osdeps information of +info+ into +self+. If packages are
        # defined in both OSDependencies objects, the information in +info+
        # takes precedence
        def merge(info)
            root_dir = nil
            @definitions = definitions.merge(info.definitions) do |h, v1, v2|
                if v1 != v2
                    root_dir ||= "#{Autoproj.root_dir}/"
                    old = source_of(h).gsub(root_dir, '')
                    new = info.source_of(h).gsub(root_dir, '')
                    Autoproj.warn("osdeps definition for #{h}, previously defined in #{old} overridden by #{new}")
                end
                v2
            end
            @sources = sources.merge(info.sources)
            @all_definitions = all_definitions.merge(info.all_definitions) do |package_name, all_defs, new_all_defs|
                all_defs = all_defs.dup
                new_all_defs = new_all_defs.dup
                new_all_defs.delete_if do |files, data|
                    if entry = all_defs.find { |_, d| d == data }
                        entry[0] |= files
                    end
                end
                all_defs.concat(new_all_defs)
            end
        end

        # Perform some sanity checks on the given osdeps definitions
        def self.verify_definitions(hash, path = [])
            hash.each do |key, value|
                if value && !key.kind_of?(String)
                    raise ArgumentError, "invalid osdeps definition: found an #{key.class} as a key in #{path.join("/")}. Don't forget to put quotes around numbers"
                elsif !value && (key.kind_of?(Hash) || key.kind_of?(Array))
                    verify_definitions(key)
                end
                next if !value

                if value.kind_of?(Array) || value.kind_of?(Hash)
                    verify_definitions(value, (path + [key]))
                else
                    if !value.kind_of?(String)
                        raise ArgumentError, "invalid osdeps definition: found an #{value.class} as a value in #{path.join("/")}. Don't forget to put quotes around numbers"
                    end
                end
            end
        end

        # Returns true if it is possible to install packages for the operating
        # system on which we are installed
        def self.supported_operating_system?
            if @supported_operating_system.nil?
                os_names, _ = operating_system
                @supported_operating_system =
                    if !os_names then false
                    else
                        os_names.any? { |os_name| OS_PACKAGE_HANDLERS.has_key?(os_name) }
                    end
            end
            return @supported_operating_system
        end

        # Used mainly during testing to bypass the operating system
        # autodetection
        def self.operating_system=(values)
            @supported_operating_system = nil
            @operating_system = values
        end

        # Autodetects the operating system name and version
        #
        # +osname+ is the operating system name, all in lowercase (e.g. ubuntu,
        # arch, gentoo, debian)
        #
        # +versions+ is a set of names that describe the OS version. It includes
        # both the version number (as a string) and/or the codename if there is
        # one.
        #
        # Examples: ['debian', ['sid', 'unstable']] or ['ubuntu', ['lucid lynx', '10.04']]
        def self.operating_system(options = Hash.new)
            # Validate the options. We check on the availability of
            # validate_options as to not break autoproj_bootstrap (in which
            # validate_options is not available)
            options =
                if Kernel.respond_to?(:validate_options)
                    Kernel.validate_options options, :force => false
                else
                    options.dup
                end

            if options[:force]
                @operating_system = nil
            else
                if !@operating_system.nil?
                    return @operating_system
                elsif Autoproj.has_config_key?('operating_system') && !(user_os = ENV['AUTOPROJ_OS'])
                    os = Autoproj.user_config('operating_system')
                    if os.respond_to?(:to_ary)
                        if os[0].respond_to?(:to_ary) && os[0].all? { |s| s.respond_to?(:to_str) } &&
                           os[1].respond_to?(:to_ary) && os[1].all? { |s| s.respond_to?(:to_str) }
                           @operating_system = os
                           return os
                        end
                    end
                end
            end

            if user_os = ENV['AUTOPROJ_OS']
                if user_os.empty?
                    @operating_system = false
                else
                    names, versions = user_os.split(':')
                    @operating_system = [names.split(','), versions.split(',')]
                end
            else
                Autoproj.message "  autodetecting the operating system"
                name, versions = os_from_lsb
                if name
                    if name != "debian"
                        if File.exists?("/etc/debian_version")
                            @operating_system = [[name, "debian"], versions]
                        else
                            @operating_system = [[name], versions]
                        end
                    end
                end
            end

            if @operating_system.nil?
                # Need to do some heuristics unfortunately
                @operating_system =
                    if File.exists?('/etc/debian_version')
                        codenames = [File.read('/etc/debian_version').strip]
                        if codenames.first =~ /sid/
                            versions = codenames + ["unstable", "sid"]
                        end
                        [['debian'], versions]
                    elsif File.exists?('/etc/fedora-release')
                        release_string = File.read('/etc/fedora-release').strip
                        release_string =~ /Fedora release (\d+)/
                        version = $1
                        [['fedora'], [version]]
                    elsif File.exists?('/etc/gentoo-release')
                        release_string = File.read('/etc/gentoo-release').strip
                        release_string =~ /^.*([^\s]+)$/
                            version = $1
                        [['gentoo'], [version]]
                    elsif File.exists?('/etc/arch-release')
                        [['arch'], []]
                    end
            end

            if !@operating_system
                return
            end

            # Normalize the names to lowercase
            names, versions = @operating_system[0], @operating_system[1]
            names    = names.map(&:downcase)
            versions = versions.map(&:downcase)
            if !versions.include?('default')
                versions += ['default']
            end

            @operating_system = [names, versions]
            Autoproj.change_option('operating_system', @operating_system, true)
            @operating_system
        end

        def self.os_from_lsb
            has_lsb_release = `which lsb_release`
            return unless $?.success?

            distributor = `lsb_release -i -s`
            distributor = distributor.strip.downcase
            codename    = `lsb_release -c -s`.strip.downcase
            version     = `lsb_release -r -s`.strip.downcase

            return [distributor, [codename, version]]
        end

        # Return the list of packages that should be installed for +name+
        #
        # The following two simple return values are possible:
        #
        # nil:: +name+ has no definition
        # []:: +name+ has no definition on this OS and/or for this specific OS
        #      version
        #
        # In all other cases, the method returns an array of triples:
        #
        #   [package_handler, status, package_list]
        #
        # where status is FOUND_PACKAGES if +package_list+ is the list of
        # packages that should be installed with +package_handler+ for +name+,
        # and FOUND_NONEXISTENT if the nonexistent keyword is used for this OS
        # name and version. The package list might be empty even if status ==
        # FOUND_PACKAGES, for instance if the ignore keyword is used.
        def resolve_package(name)
            while OSDependencies.aliases.has_key?(name)
                name = OSDependencies.aliases[name]
            end

            os_names, os_versions = OSDependencies.operating_system

            dep_def = definitions[name]
            if !dep_def
                return nil
            end

            # Partition the found definition in all entries that are interesting
            # for us: toplevel os-independent package managers, os-dependent
            # package managers and os-independent package managers selected by
            # OS or version
            if !os_names
                os_names = ['default']
                os_versions = ['default']
            end

            package_handler_names = package_handlers.keys

            result = []
            found, pkg = partition_osdep_entry(name, dep_def, nil, (package_handler_names - os_package_handler.names), os_names, os_versions)
            if found
                result << [os_package_handler, found, pkg]
            end

            # NOTE: package_handlers might contain the same handler multiple
            # times (when a package manager has multiple names). That's why we
            # do a to_set.each
            package_handlers.each_value.to_set.each do |handler|
                found, pkg = partition_osdep_entry(name, dep_def, handler.names, [], os_names, os_versions)
                if found
                    result << [handler, found, pkg]
                end
            end

            # Recursive resolutions
            found, pkg = partition_osdep_entry(name, dep_def, ['osdep'], [], os_names, os_versions)
            if found
                pkg.each do |pkg_name|
                    result.concat(resolve_package(pkg_name))
                end
            end

            result.map do |handler, status, entries|
                if handler.respond_to?(:parse_package_entry)
                    [handler, status, entries.map { |s| handler.parse_package_entry(s) }]
                else
                    [handler, status, entries]
                end
            end
        end

        # Value returned by #resolve_package and #partition_osdep_entry in
        # the status field. See the documentation of these methods for more
        # information
        FOUND_PACKAGES = 0
        # Value returned by #resolve_package and #partition_osdep_entry in
        # the status field. See the documentation of these methods for more
        # information
        FOUND_NONEXISTENT = 1

        # Helper method that parses the osdep definition to split between the
        # parts needed for this OS and specific package handlers.
        #
        # +osdep_name+ is the name of the osdep. It is used to resolve explicit
        # mentions of a package handler, i.e. so that:
        #
        #   pkg: gem
        #
        # is resolved as the 'pkg' package to be installed by the 'gem' handler
        #
        # +dep_def+ is the content to parse. It can be a string, array or hash
        #
        # +handler_names+ is a list of entries that we are looking for. If it is
        # not nil, only entries that explicitely refer to +handler_names+ will
        # be browsed, i.e. in:
        #
        #   pkg:
        #       - test: 1
        #       - [a, list, of, packages]
        #
        #   partition_osdep_entry('osdep_name', data, ['test'], [])
        #
        # will ignore the toplevel list of packages, while
        #
        #   partition_osdep_entry('osdep_name', data, nil, [])
        #
        # will return it.
        #
        # +excluded+ is a list of branches that should be ignored during
        # parsing. It is used to e.g. ignore 'gem' when browsing for the main OS
        # package list. For instance, in
        #
        #   pkg:
        #       - test
        #       - [a, list, of, packages]
        #
        #   partition_osdep_entry('osdep_name', data, nil, ['test'])
        #
        # the returned value will only include the list of packages (and not
        # 'test')
        #
        # The rest of the arguments are array of strings that contain list of
        # keys to browse for (usually, the OS names and version)
        #
        # The return value is either nil if no packages were found, or a pair
        # [status, package_list] where status is FOUND_NONEXISTENT if the
        # nonexistent keyword was found, and FOUND_PACKAGES if either packages
        # or the ignore keyword were found.
        #
        def partition_osdep_entry(osdep_name, dep_def, handler_names, excluded, *keys)
            keys, *additional_keys = *keys
            keys ||= []
            found = false
            nonexistent = false
            result = []
            found_keys = Hash.new
            Array(dep_def).each do |names, values|
                if !values
                    # Raw array of packages. Possible only if we are not at toplevel
                    # (i.e. if we already have a handler)
                    if names == 'ignore'
                        found = true if !handler_names
                    elsif names == 'nonexistent'
                        nonexistent = true if !handler_names
                    elsif !handler_names && names.kind_of?(Array)
                        result.concat(result)
                        found = true
                    elsif names.respond_to?(:to_str)
                        if excluded.include?(names)
                        elsif handler_names && handler_names.include?(names)
                            result << osdep_name
                            found = true
                        elsif !handler_names
                            result << names
                            found = true
                        end
                    elsif names.respond_to?(:to_hash)
                        rec_found, rec_result = partition_osdep_entry(osdep_name, names, handler_names, excluded, keys, *additional_keys)
                        if rec_found == FOUND_NONEXISTENT then nonexistent = true
                        elsif rec_found == FOUND_PACKAGES then found = true
                        end
                        result.concat(rec_result)
                    end
                else
                    if names.respond_to?(:to_str) # names could be an array already
                        names = names.split(',')
                    end

                    if handler_names
                        if matching_name = handler_names.find { |k| names.any? { |name_tag| k == name_tag.downcase } }
                            rec_found, rec_result = partition_osdep_entry(osdep_name, values, nil, excluded, keys, *additional_keys)
                            if rec_found == FOUND_NONEXISTENT then nonexistent = true
                            elsif rec_found == FOUND_PACKAGES then found = true
                            end
                            result.concat(rec_result)
                        end
                    end

                    matching_name = keys.find { |k| names.any? { |name_tag| k == name_tag.downcase } }
                    if matching_name
                        rec_found, rec_result = partition_osdep_entry(osdep_name, values, handler_names, excluded, *additional_keys)
                        # We only consider the first highest-priority entry,
                        # regardless of whether it has some packages for us or
                        # not
                        idx = keys.index(matching_name)
                        if !rec_found
                            if !found_keys.has_key?(idx)
                                found_keys[idx] = nil
                            end
                        else
                            found_keys[idx] ||= [0, []]
                            found_keys[idx][0] += rec_found
                            found_keys[idx][1].concat(rec_result)
                        end
                    end
                end
            end
            first_entry = found_keys.keys.sort.first
            found_keys = found_keys[first_entry]
            if found_keys
                if found_keys[0] > 0
                    nonexistent = true
                else
                    found = true
                end
                result.concat(found_keys[1])
            end

            found =
                if nonexistent then FOUND_NONEXISTENT
                elsif found then FOUND_PACKAGES
                else false
                end

            return found, result
        end

        class MissingOSDep < ConfigError; end

        # Resolves the given OS dependencies into the actual packages that need
        # to be installed on this particular OS.
        #
        # Raises ConfigError if some packages can't be found or if the
        # nonexistent keyword was found for some of them
        def resolve_os_dependencies(dependencies)
            all_packages = []
            dependencies.each do |name|
                result = resolve_package(name)
                if !result
                    raise MissingOSDep.new, "there is no osdeps definition for #{name}"
                end

                if result.empty?
                    if OSDependencies.supported_operating_system?
                        os_names, os_versions = OSDependencies.operating_system
                        raise MissingOSDep.new, "there is an osdeps definition for #{name}, but not for this operating system and version (resp. #{os_names.join(", ")} and #{os_versions.join(", ")})"
                    end
                    result = [[os_package_handler, FOUND_PACKAGES, [name]]]
                end

                result.each do |handler, status, packages|
                    if status == FOUND_NONEXISTENT
                        raise MissingOSDep.new, "there is an osdep definition for #{name}, and it explicitely states that this package does not exist on your OS"
                    end
                    if entry = all_packages.find { |h, _| h == handler }
                        entry[1].concat(packages)
                    else
                        all_packages << [handler, packages]
                    end
                end
            end

            all_packages.delete_if do |handler, pkg|
                pkg.empty?
            end
            return all_packages
        end


        # Returns true if +name+ is an acceptable OS package for this OS and
        # version
        def has?(name)
            status = availability_of(name)
            status == AVAILABLE || status == IGNORE
        end

        # Value returned by #availability_of if the required package has no
        # definition
        NO_PACKAGE       = 0
        # Value returned by #availability_of if the required package has
        # definitions, but not for this OS name or version
        WRONG_OS         = 1
        # Value returned by #availability_of if the required package has
        # definitions, but the local OS is unknown
        UNKNOWN_OS       = 2
        # Value returned by #availability_of if the required package has
        # definitions, but the nonexistent keyword was used for this OS
        NONEXISTENT      = 3
        # Value returned by #availability_of if the required package is
        # available
        AVAILABLE        = 4
        # Value returned by #availability_of if the required package is
        # available, but no package needs to be installed to have it
        IGNORE           = 5

        # If +name+ is an osdeps that is available for this operating system,
        # returns AVAILABLE. Otherwise, returns one of:
        #
        # NO_PACKAGE:: the package has no definitions
        # WRONG_OS:: the package has a definition, but not for this OS
        # UNKNOWN_OS:: the package has a definition, but the local OS is unknown
        # NONEXISTENT:: the package has a definition, but the 'nonexistent'
        #               keyword was found for this OS
        # AVAILABLE:: the package is available for this OS
        # IGNORE:: the package is available for this OS, but no packages need to
        #          be installed for it
        def availability_of(name)
            resolved = resolve_package(name)
            if !resolved
                return NO_PACKAGE
            end

            if resolved.empty?
                if !OSDependencies.operating_system
                    return UNKNOWN_OS
                elsif !OSDependencies.supported_operating_system?
                    return AVAILABLE
                else return WRONG_OS
                end
            end

            resolved = resolved.delete_if { |_, status, list| status == FOUND_PACKAGES && list.empty? }
            failed = resolved.find_all do |handler, status, list|
                status == FOUND_NONEXISTENT
            end
            if failed.empty?
                if resolved.empty?
                    return IGNORE
                else
                    return AVAILABLE
                end
            else
                return NONEXISTENT
            end
        end

        HANDLE_ALL  = 'all'
        HANDLE_RUBY = 'ruby'
        HANDLE_OS   = 'os'
        HANDLE_NONE = 'none'

        def self.osdeps_mode_option_unsupported_os
            long_doc =<<-EOT
The software packages that autoproj will have to build may require other
prepackaged softwares (a.k.a. OS dependencies) to be installed (RubyGems
packages, packages from your operating system/distribution, ...). Autoproj is
usually able to install those automatically, but unfortunately your operating
system is not (yet) supported by autoproj's osdeps mechanism, it can only offer
you some limited support.

RubyGem packages are a cross-platform mechanism, and are therefore supported.
However, you will have to install the kind of OS dependencies (so-called OS
packages)

This option is meant to allow you to control autoproj's behaviour while handling
OS dependencies.

* if you say "ruby", the RubyGem packages will be installed.
* if you say "none", autoproj will not do anything related to the OS
  dependencies.

As any configuration value, the mode can be changed anytime by calling
an autoproj operation with the --reconfigure option (e.g. autoproj update
--reconfigure).

Finally, OS dependencies can be installed by calling "autoproj osdeps"
with the corresponding option (--all, --ruby, --os or --none). Calling
"autoproj osdeps" without arguments will also give you information as
to what you should install to compile the software successfully.

So, what do you want ? (ruby or none)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (ruby, none) ?", long_doc.strip ]

	    Autoproj.configuration_option 'osdeps_mode', 'string',
		:default => 'ruby',
		:doc => message,
                :possible_values => %w{ruby none},
                :lowercase => true
        end

        def self.osdeps_mode_option_supported_os
            long_doc =<<-EOT
The software packages that autoproj will have to build may require other
prepackaged softwares (a.k.a. OS dependencies) to be installed (RubyGems
packages, packages from your operating system/distribution, ...). Autoproj
is able to install those automatically for you.

Advanced users may want to control this behaviour. Additionally, the
installation of some packages require administration rights, which you may
not have. This option is meant to allow you to control autoproj's behaviour
while handling OS dependencies.

* if you say "all", it will install all packages automatically.
  This requires root access thru 'sudo'
* if you say "ruby", only the Ruby packages will be installed.
  Installing these packages does not require root access.
* if you say "os", only the OS-provided packages will be installed.
  Installing these packages requires root access.
* if you say "none", autoproj will not do anything related to the
  OS dependencies.

As any configuration value, the mode can be changed anytime by calling
an autoproj operation with the --reconfigure option (e.g. autoproj update
--reconfigure).

Finally, OS dependencies can be installed by calling "autoproj osdeps"
with the corresponding option (--all, --ruby, --os or --none).

So, what do you want ? (all, ruby, os or none)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, ruby, os, none) ?", long_doc.strip ]

	    Autoproj.configuration_option 'osdeps_mode', 'string',
		:default => 'all',
		:doc => message,
                :possible_values => %w{all ruby os none},
                :lowercase => true
        end

        def self.define_osdeps_mode_option
            if supported_operating_system?
                osdeps_mode_option_supported_os
            else
                osdeps_mode_option_unsupported_os
            end
        end

        def self.osdeps_mode_string_to_value(string)
            string = string.downcase
            case string
            when 'all'  then HANDLE_ALL
            when 'ruby' then HANDLE_RUBY
            when 'os'   then HANDLE_OS
            when 'none' then HANDLE_NONE
            else raise ArgumentError, "invalid osdeps mode string '#{string}'"
            end
        end

        # If set to true (the default), #install will try to remove the list of
        # already uptodate packages from the installed packages. Set to false to
        # install all packages regardless of their status
        attr_writer :filter_uptodate_packages

        # If set to true (the default), #install will try to remove the list of
        # already uptodate packages from the installed packages. Use
        # #filter_uptodate_packages= to set it to false to install all packages
        # regardless of their status
        def filter_uptodate_packages?
            !!@filter_uptodate_packages
        end

        # Override the osdeps mode
        def osdeps_mode=(value)
            @osdeps_mode = OSDependencies.osdeps_mode_string_to_value(value)
        end

        # Returns the osdeps mode chosen by the user
        def osdeps_mode
            # This has two uses. It caches the value extracted from the
            # AUTOPROJ_OSDEPS_MODE and/or configuration file. Moreover, it
            # allows to override the osdeps mode by using
            # OSDependencies#osdeps_mode=
            if @osdeps_mode
                return @osdeps_mode
            end

            @osdeps_mode = OSDependencies.osdeps_mode
        end

        def self.osdeps_mode
            while true
                mode =
                    if !Autoproj.has_config_key?('osdeps_mode') &&
                        mode_name = ENV['AUTOPROJ_OSDEPS_MODE']
                        begin OSDependencies.osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode given through AUTOPROJ_OSDEPS_MODE (#{mode})"
                            nil
                        end
                    else
                        mode_name = Autoproj.user_config('osdeps_mode')
                        begin OSDependencies.osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode stored in configuration file"
                            nil
                        end
                    end

                if mode
                    @osdeps_mode = mode
                    Autoproj.change_option('osdeps_mode', mode_name, true)
                    return mode
                end

                # Invalid configuration values. Retry
                Autoproj.reset_option('osdeps_mode')
                ENV['AUTOPROJ_OSDEPS_MODE'] = nil
            end
        end

        # The set of packages that have already been installed
        attr_reader :installed_packages

        def installs_os_packages?
            osdeps_mode == HANDLE_ALL || osdeps_mode == HANDLE_OS
        end

        def installs_ruby_packages?
            osdeps_mode == HANDLE_ALL || osdeps_mode == HANDLE_RUBY
        end


        # Requests the installation of the given set of packages
        def install(packages, package_osdeps = Hash.new)
            os_package_handler.enabled = installs_os_packages?
            os_package_handler.silent = self.silent?
            package_handlers['gem'].enabled = installs_ruby_packages?
            package_handlers.each_value do |v|
                v.silent = self.silent?
            end

            # Remove the set of packages that have already been installed 
            packages = packages.to_set - installed_packages
            return false if packages.empty?

            packages = resolve_os_dependencies(packages)
            packages = packages.map do |handler, list|
                if filter_uptodate_packages? && handler.respond_to?(:filter_uptodate_packages)
                    list = handler.filter_uptodate_packages(list)
                end

                if !list.empty?
                    [handler, list]
                end
            end.compact
            return false if packages.empty?

            # Install OS packages first, as the other package handlers might
            # depend on OS packages
            os_packages, other_packages = packages.partition { |handler, list| handler == os_package_handler }
            [os_packages, other_packages].each do |packages|
                packages.each do |handler, list|
                    handler.install(list)
                    @installed_packages |= list.to_set
                end
            end
            true
        end
    end
end

