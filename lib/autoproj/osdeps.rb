require 'tempfile'
require 'json'
module Autoproj
    # Module that contains the package manager implementations for the
    # OSDependencies class
    module PackageManagers
        # Base class for all package managers. Subclasses must add the
        # #install(packages) method and may add the
        # #filter_uptodate_packages(packages) method
        #
        # Package managers must be registered in PACKAGE_HANDLERS and
        # (if applicable) OS_PACKAGE_HANDLERS.
        class Manager
            # @return [Array<String>] the various names this package manager is
            #   known about
            attr_reader :names

            attr_writer :enabled
            def enabled?; !!@enabled end

            attr_writer :silent
            def silent?; !!@silent end

            # Create a package manager registered with various names
            #
            # @param [Array<String>] names the package manager names. It MUST be
            #   different from the OS names that autoproj uses. See the comment
            #   for OS_PACKAGE_HANDLERS for an explanation
            def initialize(names = [])
                @names = names.dup
                @enabled = true
                @silent = true
            end

            # The primary name for this package manager
            def name
                names.first
            end

            # Overload to perform initialization of environment variables in
            # order to have a properly functioning package manager
            #
            # This is e.g. needed for python pip or rubygems
            def self.initialize_environment
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
            def self.execute(script, with_locking, with_root)
                if with_locking
                    File.open('/tmp/autoproj_osdeps_lock', 'w') do |lock_io|
                        begin
                            while !lock_io.flock(File::LOCK_EX | File::LOCK_NB)
                                Autoproj.message "  waiting for other autoproj instances to finish their osdeps installation"
                                sleep 5
                            end
                            return execute(script, false,with_root)
                        ensure
                            lock_io.flock(File::LOCK_UN)
                        end
                    end
                end
                
                sudo = Autobuild.tool_in_path('sudo')
                Tempfile.open('osdeps_sh') do |io|
                    io.puts "#! /bin/bash"
                    io.puts GAIN_ROOT_ACCESS % [sudo] if with_root
                    io.write script
                    io.flush
                    Autobuild::Subprocess.run 'autoproj', 'osdeps', '/bin/bash', io.path
                end
            end

            GAIN_ROOT_ACCESS = <<-EOSCRIPT
# Gain root access using sudo
if test `id -u` != "0"; then
    exec %s /bin/bash $0 "$@"

fi
            EOSCRIPT

            # Overrides the {#needs_locking?} flag
            attr_writer :needs_locking
            # Whether two autoproj instances can run this package manager at the
            # same time
            #
            # This declares if this package manager cannot be used concurrently.
            # If it is the case, autoproj will ensure that there is no two
            # autoproj instances running this package manager at the same time
            # 
            # @return [Boolean]
            # @see needs_locking=
            def needs_locking?; !!@needs_locking end

            # Overrides the {#needs_root?} flag
            attr_writer :needs_root
            # Whether this package manager needs root access.
            #
            # This declares if the command line(s) for this package manager
            # should be started as root. Root access is provided using sudo
            # 
            # @return [Boolean]
            # @see needs_root=
            def needs_root?; !!@needs_root end

            # Command line used by autoproj to install packages
            #
            # Since it is to be used for automated install by autoproj, it
            # should not require any interaction with the user. When generating
            # the command line, the %s slot is replaced by the quoted package
            # name(s).
            #
            # @return [String] a command line pattern that allows to install
            #   packages without user interaction. It is used when a package
            #   should be installed by autoproj automatically
            attr_reader :auto_install_cmd
            # Command line displayed to the user to install packages
            #
            # When generating the command line, the %s slot is replaced by the
            # quoted package name(s).
            #
            # @return [String] a command line pattern that allows to install
            #   packages with user interaction. It is displayed to the
            #   user when it chose to not let autoproj install packages for this
            #   package manager automatically
            attr_reader :user_install_cmd

            # @param [Array<String>] names the package managers names, see
            #   {#names}
            # @param [Boolean] needs_locking whether this package manager can be
            #   started by two separate autoproj instances at the same time. See
            #   {#needs_locking?}
            # @param [String] user_install_cmd the user-visible command line. See
            #   {#user_install_cmd}
            # @param [String] auto_install_cmd the command line used by autoproj
            #   itself, see {#auto_install_cmd}.
            # @param [Boolean] needs_root if the command lines should be started
            #   as root or not. See {#needs_root?}
            def initialize(names, needs_locking, user_install_cmd, auto_install_cmd,needs_root=true)
                super(names)
                @needs_locking, @user_install_cmd, @auto_install_cmd,@needs_root =
                    needs_locking, user_install_cmd, auto_install_cmd, needs_root
            end

            # Generate the shell script that would allow the user to install
            # the given packages
            #
            # @param [Array<String>] os_packages the name of the packages to be
            #   installed
            # @option options [String] :user_install_cmd (#user_install_cmd) the
            #   command-line pattern that should be used to generate the script.
            #   If given, it overrides the default value stored in
            #   {#user_install_cmd]
            def generate_user_os_script(os_packages, options = Hash.new)
                user_install_cmd = options[:user_install_cmd] || self.user_install_cmd
                if user_install_cmd
                    (user_install_cmd % [os_packages.join("' '")])
                else generate_auto_os_script(os_packages)
                end
            end

            # Generate the shell script that should be executed by autoproj to
            # install the given packages
            #
            # @param [Array<String>] os_packages the name of the packages to be
            #   installed
            # @option options [String] :auto_install_cmd (#auto_install_cmd) the
            #   command-line pattern that should be used to generate the script.
            #   If given, it overrides the default value stored in
            #   {#auto_install_cmd]
            def generate_auto_os_script(os_packages, options = Hash.new)
                auto_install_cmd = options[:auto_install_cmd] || self.auto_install_cmd
                (auto_install_cmd % [os_packages.join("' '")])
            end

            # Handles interaction with the user
            #
            # This method will verify whether the user required autoproj to
            # install packages from this package manager automatically. It
            # displays a relevant message if it is not the case.
            #
            # @return [Boolean] true if the packages should be installed
            #   automatically, false otherwise
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

            # Install packages using this package manager
            #
            # @param [Array<String>] packages the name of the packages that
            #   should be installed
            # @option options [String] :user_install_cmd (#user_install_cmd) the
            #   command line that should be displayed to the user to install said
            #   packages. See the option in {#generate_user_os_script}
            # @option options [String] :auto_install_cmd (#auto_install_cmd) the
            #   command line that should be used by autoproj to install said
            #   packages. See the option in {#generate_auto_os_script}
            # @return [Boolean] true if packages got installed, false otherwise
            def install(packages, options = Hash.new)
                handled_os = OSDependencies.supported_operating_system?
                if handled_os
                    shell_script = generate_auto_os_script(packages, options)
                    user_shell_script = generate_user_os_script(packages, options)
                end
                if osdeps_interaction(packages, user_shell_script)
                    Autoproj.message "  installing OS packages: #{packages.sort.join(", ")}"

                    if Autoproj.verbose
                        Autoproj.message "Generating installation script for non-ruby OS dependencies"
                        Autoproj.message shell_script
                    end
                    ShellScriptManager.execute(shell_script, needs_locking?,needs_root?)
                    return true
                end
                false
            end
        end

        # Package manager interface for systems that use port (i.e. MacPorts/Darwin) as
        # their package manager
        class PortManager < ShellScriptManager
            def initialize
                super(['macports'], true,
                        "port install '%s'",
                        "port install '%s'")
            end
        end

        # Package manager interface for Mac OS using homebrew as
        # its package manager
        class HomebrewManager < ShellScriptManager
            def initialize
                super(['brew'], true,
                        "brew install '%s'",
                        "brew install '%s'",
                        false)
            end

            def filter_uptodate_packages(packages)
                # TODO there might be duplicates in packages which should be fixed
                # somewhere else
                packages = packages.uniq
                result = `brew info --json=v1 '#{packages.join("' '")}'`
                result = begin
                             result = JSON.parse(result)
                             if packages.size == 1
                                 [result]
                             else
                                 result
                             end
                         rescue JSON::ParserError
                             if result && !result.empty?
                                 Autoproj.warn "Error while parsing result of brew info --json=v1"
                             else
                                 # one of the packages is unknown fallback to install all
                                 # packaes which will complain about it
                             end
                             return packages
                         end
                # fall back if something else went wrong
                if packages.size != result.size
                    Autoproj.warn "brew info returns less or more packages when requested. Falling back to install all packages"
                    return packages
                end

                new_packages = []
                result.each do |pkg|
                    new_packages << pkg["name"] if pkg["installed"].empty?
                end
                new_packages
            end
        end

        # Package manager interface for systems that use pacman (i.e. arch) as
        # their package manager
        class PacmanManager < ShellScriptManager
            def initialize
                super(['pacman'], true,
                        "pacman -Sy --needed '%s'",
                        "pacman -Sy --needed --noconfirm '%s'")
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

        #Package manger for OpenSuse and Suse (untested)
        class ZypperManager < ShellScriptManager
            def initialize
                super(['zypper'], true,
                        "zypper install '%s'",
                        "zypper -n install '%s'")
            end

            def filter_uptodate_packages(packages)
                result = `LANG=C rpm -q --whatprovides '#{packages.join("' '")}'`
                has_all_pkgs = $?.success?

                if !has_all_pkgs
                    return packages # let zypper filter, we need root now anyways
                else 
                    return []
                end
            end

            def install(packages)
                patterns, packages = packages.partition { |pkg| pkg =~ /^@/ }
                patterns = patterns.map { |str| str[1..-1] }
                result = false
                if !patterns.empty?
                    result |= super(patterns,
                                    :auto_install_cmd => "zypper --non-interactive install --type pattern '%s'",
                                    :user_install_cmd => "zypper install --type pattern '%s'")
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

        # Package manager interface for systems that use APT and dpkg for
        # package management
        class AptDpkgManager < ShellScriptManager
            attr_accessor :status_file

            def initialize(status_file = "/var/lib/dpkg/status")
                @status_file = status_file
                super(['apt-dpkg'], true,
                      "apt-get install '%s'",
                      "export DEBIAN_FRONTEND=noninteractive; apt-get install -y '%s'")
            end

            # On a dpkg-enabled system, checks if the provided package is installed
            # and returns true if it is the case
            def installed?(package_name)
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

            # Filters all paths that come from other autoproj installations out
            # of GEM_PATH
            def self.initialize_environment
                Autobuild::ORIGINAL_ENV['GEM_PATH'] =
                    (ENV['GEM_PATH'] || "").split(File::PATH_SEPARATOR).find_all do |p|
                        !Autoproj.in_autoproj_installation?(p)
                    end.join(File::PATH_SEPARATOR)
                Autobuild.env_inherit 'GEM_PATH'
                Autobuild.env_init_from_env 'GEM_PATH'

                orig_gem_path = Autobuild::ORIGINAL_ENV['GEM_PATH'].split(File::PATH_SEPARATOR)
                Autobuild::SYSTEM_ENV['GEM_PATH'] = Gem.default_path
                Autobuild::ORIGINAL_ENV['GEM_PATH'] = orig_gem_path.join(File::PATH_SEPARATOR)

                Autoproj.manifest.each_reused_autoproj_installation do |p|
                    p_gems = File.join(p, '.gems')
                    if File.directory?(p_gems)
                        Autobuild.env_add_path 'GEM_PATH', p_gems
                        Autobuild.env_add_path 'PATH', File.join(p_gems, 'bin')
                    end
                end
                Autobuild.env_add_path 'GEM_PATH', gem_home
                Autobuild.env_set 'GEM_HOME', gem_home
                Autobuild.env_add_path 'PATH', "#{gem_home}/bin"

                # Now, reset the directories in our own RubyGems instance
                Gem.paths = ENV

                # If there is a cache directory, make sure .gems/cache points to
                # it (there are no programmatic ways to override this)
                if cache = cache_dir
                    gem_cache_dir = File.join(gem_home, 'cache')
                    if !File.symlink?(gem_cache_dir) || File.readlink(gem_cache_dir) != cache
                        FileUtils.mkdir_p gem_home
                        FileUtils.rm_rf gem_cache_dir
                        Autoproj.create_symlink(cache, gem_cache_dir)
                    end
                end
            end

            # A global cache directory that should be used to avoid
            # re-downloading gems
            def self.cache_dir
                if dir = ENV['AUTOBUILD_CACHE_DIR']
                    dir = File.join(dir, 'gems')
                    FileUtils.mkdir_p dir
                    dir
                end
            end

            # Return the directory in which RubyGems package should be installed
            def self.gem_home
                ENV['AUTOPROJ_GEM_HOME'] || File.join(Autoproj.root_dir, ".gems")
            end
            
            # Returns the set of default options that are added to gem
            #
            # By default, we add --no-user-install to un-break distributions
            # like Arch that set --user-install by default (thus disabling the
            # role of GEM_HOME)
            def self.default_install_options
                @default_install_options ||= ['--no-user-install', '--no-format-executable']
            end

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

            def build_gem_cmdlines(gems)
                with_version, without_version = gems.partition { |name, v| v }

                cmdlines = []
                if !without_version.empty?
                    cmdlines << without_version.flatten
                end
                with_version.each do |name, v|
                    cmdlines << [name, "-v", v]
                end
                cmdlines
            end

            def pristine(gems)
                guess_gem_program
                base_cmdline = [Autobuild.tool_in_path('ruby'), '-S', Autobuild.tool('gem')]
                cmdlines = [
                    [*base_cmdline, 'clean'],
                ]
                cmdlines += build_gem_cmdlines(gems).map do |line|
                    base_cmdline + ["pristine", "--extensions"] + line
                end
                if gems_interaction(gems, cmdlines)
                    Autoproj.message "  restoring RubyGems: #{gems.map { |g| g.join(" ") }.sort.join(", ")}"
                    cmdlines.each do |c|
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', *c
                    end
                end
            end

            def install(gems)
                guess_gem_program

                base_cmdline = [Autobuild.tool_in_path('ruby'), '-S', Autobuild.tool('gem'), 'install', *GemManager.default_install_options]
                if !GemManager.with_doc
                    base_cmdline << '--no-rdoc' << '--no-ri'
                end

                if GemManager.with_prerelease
                    base_cmdline << "--prerelease"
                end

                cmdlines = build_gem_cmdlines(gems).map do |line|
                    base_cmdline + line
                end
                if gems_interaction(gems, cmdlines)
                    Autoproj.message "  installing/updating RubyGems dependencies: #{gems.map { |g| g.join(" ") }.sort.join(", ")}"

                    cmdlines.each do |c|
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', *c
                    end
                    gems.each do |name, v|
                        installed_gems << name
                    end
                    true
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
                        available =
                            if gem_fetcher.respond_to?(:find_matching)
                                non_prerelease = gem_fetcher.find_matching(dep, true, true).map(&:first)
                                if GemManager.with_prerelease
                                    prerelease = gem_fetcher.find_matching(dep, false, true, true).map(&:first)
                                else prerelease = Array.new
                                end
                                (non_prerelease + prerelease).
                                    map { |n, v, _| [n, v] }

                            else # Post RubyGems-2.0
                                type = if GemManager.with_prerelease then :complete
                                       else :released
                                       end

                                gem_fetcher.detect(type) do |tuple|
                                    tuple.name == name && dep.match?(tuple)
                                end.map { |tuple, _| [tuple.name, tuple.version] }
                            end
                        installed_version = installed.map(&:version).max
                        available_version = available.map { |_, v| v }.max
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
        
        Autoproj expects these Gems to be installed in #{GemManager.gem_home} This can
        be overridden by setting the AUTOPROJ_GEM_HOME environment variable manually

                EOMSG
                print "    #{Autoproj.color("Press ENTER to continue ", :bold)}"

                STDOUT.flush
                STDIN.readline
                puts
                false
            end
        end
    
        # Using pip to install python packages
        class PipManager < Manager

            attr_reader :installed_gems

            def self.initialize_environment
                Autoproj.env_set 'PYTHONUSERBASE', pip_home
            end

            # Return the directory where python packages are installed to.
            # The actual path is pip_home/lib/pythonx.y/site-packages.
            def self.pip_home
                ENV['AUTOPROJ_PYTHONUSERBASE'] || File.join(Autoproj.root_dir,".pip")
            end


            def initialize
                super(['pip'])
                @installed_pips = Set.new
            end

            def guess_pip_program
                if Autobuild.programs['pip']
                    return Autobuild.programs['pip']
                end

                Autobuild.programs['pip'] = "pip"
            end

            def install(pips)
                guess_pip_program
                if pips.is_a?(String)
                    pips = [pips]
                end

                base_cmdline = [Autobuild.tool('pip'), 'install','--user']

                cmdlines = [base_cmdline + pips]

                if pips_interaction(pips, cmdlines)
                    Autoproj.message "  installing/updating Python dependencies: "+
                        "#{pips.sort.join(", ")}"

                    cmdlines.each do |c|
                        Autobuild::Subprocess.run 'autoproj', 'osdeps', *c
                    end

                    pips.each do |p|
                        @installed_pips << p
                    end
                end
            end
            
            def pips_interaction(pips, cmdlines)
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
      #{Autoproj.color("The build process and/or the packages require some Python packages to be installed", :bold)}
      #{Autoproj.color("and you required autoproj to not do it itself", :bold)}
        The following command line can be used to install them manually
        
          #{cmdlines.map { |c| c.join(" ") }.join("\n      ")}
        
        Autoproj expects these Python packages to be installed in #{PipManager.pip_home} This can
        be overridden by setting the AUTOPROJ_PYTHONUSERBASE environment variable manually

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
            "ruby#{RUBY_VERSION.split('.')[0, 2].join("")}"
        end

        def self.autodetect_ruby_program
            ruby = RbConfig::CONFIG['RUBY_INSTALL_NAME']
            ruby_bindir = RbConfig::CONFIG['bindir']
            ruby_executable = File.join(ruby_bindir, ruby)
            Autobuild.programs['ruby'] = ruby_executable
            ruby_executable
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

        def load_default
            merge(self.class.load_default)
        end

        PACKAGE_HANDLERS = [PackageManagers::AptDpkgManager,
            PackageManagers::GemManager,
            PackageManagers::EmergeManager,
            PackageManagers::PacmanManager,
            PackageManagers::HomebrewManager,
            PackageManagers::YumManager,
            PackageManagers::PortManager,
            PackageManagers::ZypperManager,
            PackageManagers::PipManager]
        
        # Mapping from OS name to package manager name
        #
        # Package handlers and OSes MUST have different names. The former are
        # used to resolve packages and the latter to resolve OSes in the osdeps.
        # Since one can force the use of a package manager in any OS by adding a
        # package manager entry, as e.g.
        #
        # ubuntu:
        #    homebrew: package
        #
        # we need to be able to separate between OS and package manager names.
        OS_PACKAGE_HANDLERS = {
            'debian' => 'apt-dpkg',
            'gentoo' => 'emerge',
            'arch' => 'pacman',
            'fedora' => 'yum',
            'macos-port' => 'macports',
            'macos-brew' => 'brew',
            'opensuse' => 'zypper'
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

        # Returns the name of all known OS packages
        #
        # It includes even the packages for which there are no definitions on
        # this OS
        def all_package_names
            all_definitions.keys
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

                    # Warn if the new osdep definition resolves to a different
                    # set of packages than the old one
                    old_resolved = resolve_package(h).inject(Hash.new) do |osdep_h, (handler, status, list)|
                        osdep_h[handler.name] = [status, list]
                        osdep_h
                    end
                    new_resolved = info.resolve_package(h).inject(Hash.new) do |osdep_h, (handler, status, list)|
                        osdep_h[handler.name] = [status, list]
                        osdep_h
                    end
                    if old_resolved != new_resolved
                        Autoproj.warn("osdeps definition for #{h}, previously defined in #{old} overridden by #{new}")
                    end
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

        def self.guess_operating_system
            if File.exists?('/etc/debian_version')
                versions = [File.read('/etc/debian_version').strip]
                if versions.first =~ /sid/
                    versions = ["unstable", "sid"]
                end
                [['debian'], versions]
            elsif File.exists?('/etc/redhat-release')
                release_string = File.read('/etc/redhat-release').strip
                release_string =~ /(.*) release ([\d.]+)/
                name = $1.downcase
                version = $2
                if name =~ /Red Hat Entreprise/
                    name = 'rhel'
                end
                [[name], [version]]
            elsif File.exists?('/etc/gentoo-release')
                release_string = File.read('/etc/gentoo-release').strip
                release_string =~ /^.*([^\s]+)$/
                version = $1
                [['gentoo'], [version]]
            elsif File.exists?('/etc/arch-release')
                [['arch'], []]
            elsif Autobuild.macos? 
                version=`sw_vers | head -2 | tail -1`.split(":")[1]
                manager =
                    if ENV['AUTOPROJ_MACOSX_PACKAGE_MANAGER']
                        ENV['AUTOPROJ_MACOSX_PACKAGE_MANAGER']
                    else 'macos-brew'
                    end
                if !OS_PACKAGE_HANDLERS.include?(manager)
                    known_managers = OS_PACKAGE_HANDLERS.keys.grep(/^macos/)
                    raise ArgumentError, "#{manager} is not a known MacOSX package manager. Known package managers are #{known_managers.join(", ")}"
                end

                managers = 
                    if manager == 'macos-port'
                        [manager, 'port']
                    else [manager]
                    end
                [[*managers, 'darwin'], [version.strip]]
            elsif Autobuild.windows?
                [['windows'], []]
            elsif File.exists?('/etc/SuSE-release')
                version = File.read('/etc/SuSE-release').strip
                version =~/.*VERSION\s+=\s+([^\s]+)/
                version = $1
                [['opensuse'], [version.strip]]
            end
        end

        def self.ensure_derivatives_refer_to_their_parents(names)
            names = names.dup
            version_files = Hash[
                '/etc/debian_version' => 'debian',
                '/etc/redhat-release' => 'fedora',
                '/etc/gentoo-release' => 'gentoo',
                '/etc/arch-release' => 'arch',
                '/etc/SuSE-release' => 'opensuse']
            version_files.each do |file, name|
                if File.exists?(file) && !names.include?(name)
                    names << name
                end
            end
            names
        end
        
        def self.normalize_os_representation(names, versions)
            # Normalize the names to lowercase
            names    = names.map(&:downcase)
            versions = versions.map(&:downcase)
            if !versions.include?('default')
                versions += ['default']
            end
            return names, versions
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

            if user_os = ENV['AUTOPROJ_OS']
                @operating_system =
                    if user_os.empty? then false
                    else
                        names, versions = user_os.split(':')
                        normalize_os_representation(names.split(','), versions.split(','))
                    end
                return @operating_system
            end


            if options[:force]
                @operating_system = nil
            elsif !@operating_system.nil? # @operating_system can be set to false to simulate an unknown OS
                return @operating_system
            elsif Autoproj.has_config_key?('operating_system')
                os = Autoproj.user_config('operating_system')
                if os.respond_to?(:to_ary)
                    if os[0].respond_to?(:to_ary) && os[0].all? { |s| s.respond_to?(:to_str) } &&
                       os[1].respond_to?(:to_ary) && os[1].all? { |s| s.respond_to?(:to_str) }
                       @operating_system = os
                       return os
                    end
                end
                @operating_system = nil # Invalid OS format in the configuration file
            end

            Autobuild.progress :operating_system_autodetection, "autodetecting the operating system"
            names, versions = os_from_os_release

            # Don't use the os-release information on Debian, since they
            # refuse to put enough information to detect 'unstable'
            # reliably. So, we use the heuristic method for it
            if !names || names[0] == 'debian'
                names, versions = guess_operating_system
            end
            return if !names

            names = ensure_derivatives_refer_to_their_parents(names)
            names, versions = normalize_os_representation(names, versions)

            @operating_system = [names, versions]
            Autoproj.change_option('operating_system', @operating_system, true)
            Autobuild.progress :operating_system_autodetection, "operating system: #{(names - ['default']).join(",")} - #{(versions - ['default']).join(",")}"
            @operating_system
        ensure
            Autobuild.progress_done :operating_system_autodetection
        end

        def self.os_from_os_release(filename = '/etc/os-release')
            return if !File.exists?(filename)

            fields = Hash.new
            File.readlines(filename).each do |line|
                line = line.strip
                if line.strip =~ /^(\w+)=(?:["'])?([^"']+)(?:["'])?$/
                    fields[$1] = $2
                elsif !line.empty?
                    Autoproj.warn "could not parse line '#{line.inspect}' in /etc/os-release"
                end
            end

            names = []
            versions = []
            names << fields['ID'] << fields['ID_LIKE']
            versions << fields['VERSION_ID']
            version = fields['VERSION'] || ''
            versions.concat(version.gsub(/[^\w.]/, ' ').split(' '))
            return names.compact.uniq, versions.compact.uniq
        end

        def self.os_from_lsb
            if !Autobuild.find_in_path('lsb_release')
                return
            end

            distributor = `lsb_release -i -s`
            distributor = distributor.strip.downcase
            codename    = `lsb_release -c -s`.strip.downcase
            version     = `lsb_release -r -s`.strip.downcase

            return [distributor, [codename, version]]
        end

        class InvalidRecursiveStatement < Autobuild::Exception; end

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
            os_names = os_names.dup
            os_names << 'default'

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
                    resolved = resolve_package(pkg_name)
                    if !resolved
                        raise InvalidRecursiveStatement, "osdep #{pkg_name} does not exist. It is referred to by #{name}."
                    end
                    result.concat(resolved)
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
        # @param [Array<String>] dependencies the list of osdep names that should be resolved
        # @return [Array<#install,Array<String>>] the set of packages, grouped
        #   by the package handlers that should be used to install them
        #
        # @raise MissingOSDep if some packages can't be found or if the
        #   nonexistent keyword was found for some of them
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

Some package handlers are cross-platform, and are therefore supported.  However,
you will have to install the kind of OS dependencies (so-called OS packages)

This option is meant to allow you to control autoproj's behaviour while handling
OS dependencies.

* if you say "all", all OS-independent packages are going to be installed.
* if you say "gem", the RubyGem packages will be installed.
* if you say "pip", the Pythin PIP packages will be installed.
* if you say "none", autoproj will not do anything related to the OS
  dependencies.

As any configuration value, the mode can be changed anytime by calling
  autoproj reconfigure

Finally, the "autoproj osdeps" command will give you the necessary information
about the OS packages that you will need to install manually.

So, what do you want ? (all, none or a comma-separated list of: gem pip)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, none or a comma-separated list of: gem pip) ?", long_doc.strip ]

	    Autoproj.configuration_option 'osdeps_mode', 'string',
		:default => 'ruby',
		:doc => message,
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
* if you say "pip", only the Ruby packages will be installed.
  Installing these packages does not require root access.
* if you say "gem", only the Ruby packages will be installed.
  Installing these packages does not require root access.
* if you say "os", only the OS-provided packages will be installed.
  Installing these packages requires root access.
* if you say "none", autoproj will not do anything related to the
  OS dependencies.

Finally, you can provide a comma-separated list of pip gem and os.

As any configuration value, the mode can be changed anytime by calling
  autoproj reconfigure

Finally, the "autoproj osdeps" command will give you the necessary information
about the OS packages that you will need to install manually.

So, what do you want ? (all, none or a comma-separated list of: os gem pip)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, none or a comma-separated list of: os gem pip) ?", long_doc.strip ]

	    Autoproj.configuration_option 'osdeps_mode', 'string',
		:default => 'all',
		:doc => message,
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
            string = string.to_s.downcase.split(',')
            modes = []
            string.map do |str|
                case str
                when 'all'  then modes.concat(['os', 'gem', 'pip'])
                when 'ruby' then modes << 'gem'
                when 'gem'  then modes << 'gem'
                when 'pip'  then modes << 'pip'
                when 'os'   then modes << 'os'
                when 'none' then
                else raise ArgumentError, "#{str} is not a known package handler"
                end
            end
            modes
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

        # Set up the registered package handlers according to the specified osdeps mode
        #
        # It enables/disables package handlers based on either the value
        # returned by {#osdeps_mode} or the value passed as option (the latter
        # takes precedence). Moreover, sets the handler's silent flag using
        # {#silent?}
        #
        # @option options [Array<String>] the package handlers that should be
        #   enabled. The default value is returned by {#osdeps_mode}
        # @return [Array<PackageManagers::Manager>] the set of enabled package
        #   managers
        def setup_package_handlers(options = Hash.new)
            options =
                if Kernel.respond_to?(:validate_options)
                    Kernel.validate_options options, :osdeps_mode => osdeps_mode
                else
                    options = options.dup
                    options[:osdeps_mode] ||= osdeps_mode
                    options
                end

            os_package_handler.enabled = false
            package_handlers.each_value do |handler|
                handler.enabled = false
            end
            options[:osdeps_mode].each do |m|
                if m == 'os'
                    os_package_handler.enabled = true
                elsif pkg = package_handlers[m]
                    pkg.enabled = true
                else
                    Autoproj.warn "osdep handler #{m.inspect} has no handler, available handlers are #{package_handlers.keys.map(&:inspect).sort.join(", ")}"
                end
            end
            os_package_handler.silent = self.silent?
            package_handlers.each_value do |v|
                v.silent = self.silent?
            end

            enabled_handlers = []
            if os_package_handler.enabled?
                enabled_handlers << os_package_handler
            end
            package_handlers.each_value do |v|
                if v.enabled?
                    enabled_handlers << v
                end
            end
            enabled_handlers
        end

        # Requests that packages that are handled within the autoproj project
        # (i.e. gems) are restored to pristine condition
        #
        # This is usually called as a rebuild step to make sure that all these
        # packages are updated to whatever required the rebuild
        def pristine(packages, options = Hash.new)
            setup_package_handlers(options)
            packages = resolve_os_dependencies(packages)

            _, other_packages =
                packages.partition { |handler, list| handler == os_package_handler }
            other_packages.each do |handler, list|
                if handler.respond_to?(:pristine)
                    handler.pristine(list)
                end
            end
        end

        # Requests the installation of the given set of packages
        def install(packages, options = Hash.new)
            # Remove the set of packages that have already been installed 
            packages = packages.to_set - installed_packages
            return false if packages.empty?

            setup_package_handlers(options)

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

