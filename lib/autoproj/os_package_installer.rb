require 'autoproj/package_managers/manager'
require 'autoproj/package_managers/unknown_os_manager'
require 'autoproj/package_managers/shell_script_manager'

require 'autoproj/package_managers/apt_dpkg_manager'
require 'autoproj/package_managers/emerge_manager'
require 'autoproj/package_managers/homebrew_manager'
require 'autoproj/package_managers/pacman_manager'
require 'autoproj/package_managers/pkg_manager'
require 'autoproj/package_managers/port_manager'
require 'autoproj/package_managers/yum_manager'
require 'autoproj/package_managers/zypper_manager'

require 'autoproj/package_managers/bundler_manager'
require 'autoproj/package_managers/pip_manager'

module Autoproj
    class OSPackageInstaller
        attr_reader :ws

        PACKAGE_MANAGERS = Hash[
           'apt-dpkg' => PackageManagers::AptDpkgManager,
           'gem'      => PackageManagers::BundlerManager,
           'emerge'   => PackageManagers::EmergeManager,
           'pacman'   => PackageManagers::PacmanManager,
           'brew'     => PackageManagers::HomebrewManager,
           'yum'      => PackageManagers::YumManager,
           'macports' => PackageManagers::PortManager,
           'zypper'   => PackageManagers::ZypperManager,
           'pip'      => PackageManagers::PipManager ,
           'pkg'      => PackageManagers::PkgManager
        ]

        attr_reader :os_package_resolver

        # The set of packages that have already been installed
        attr_reader :installed_packages

        # The set of resolved packages that have already been installed
        attr_reader :installed_resolved_packages

        attr_writer :silent
        def silent?; @silent end

        class << self
            attr_accessor :force_osdeps
        end

        def initialize(ws, os_package_resolver)
            @ws = ws
            @os_package_resolver = os_package_resolver
            @installed_packages = Set.new
            @installed_resolved_packages = Hash.new { |h, k| h[k] = Set.new }
            @silent = true
            @filter_uptodate_packages = true
        end

        # Returns the package manager object for the current OS
        def os_package_manager
            if !@os_package_manager
                name = os_package_resolver.os_package_manager
                @os_package_manager = package_managers[name] ||
                    PackageManagers::UnknownOSManager.new(ws)
            end
            return @os_package_manager
        end

        # Returns the set of package managers
        def package_managers
            if !@package_managers
                @package_managers = Hash.new
                PACKAGE_MANAGERS.each do |name, klass|
                    @package_managers[name] = klass.new(ws)
                end
            end
            @package_managers
        end

        def each_manager(&block)
            package_managers.each_value(&block)
        end

        HANDLE_ALL  = 'all'
        HANDLE_RUBY = 'ruby'
        HANDLE_OS   = 'os'
        HANDLE_NONE = 'none'

        def osdeps_mode_option_unsupported_os(config)
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
* if you say "pip", the Python PIP packages will be installed.
* if you say "none", autoproj will not do anything related to the OS
  dependencies.

As any configuration value, the mode can be changed anytime by calling
  autoproj reconfigure

Finally, the "autoproj osdeps" command will give you the necessary information
about the OS packages that you will need to install manually.

So, what do you want ? (all, none or a comma-separated list of: gem pip)
            EOT
            message = [ "Which prepackaged software (a.k.a. 'osdeps') should autoproj install automatically (all, none or a comma-separated list of: gem pip) ?", long_doc.strip ]

            config.declare 'osdeps_mode', 'string',
                default: 'ruby',
                doc: message,
                lowercase: true
        end

        def osdeps_mode_option_supported_os(config)
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
* if you say "pip", only the Python packages will be installed.
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

            config.declare 'osdeps_mode', 'string',
                default: 'all',
                doc: message,
                lowercase: true
        end

        def define_osdeps_mode_option
            if os_package_resolver.supported_operating_system?
                osdeps_mode_option_supported_os(ws.config)
            else
                osdeps_mode_option_unsupported_os(ws.config)
            end
        end

        def osdeps_mode_string_to_value(string)
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
            @osdeps_mode = osdeps_mode_string_to_value(value)
        end

        # Returns the osdeps mode chosen by the user
        def osdeps_mode
            # This has two uses. It caches the value extracted from the
            # AUTOPROJ_OSDEPS_MODE and/or configuration file. Moreover, it
            # allows to override the osdeps mode by using
            # OSPackageInstaller#osdeps_mode=
            if @osdeps_mode
                return @osdeps_mode
            end

            config = ws.config
            while true
                mode =
                    if !config.has_value_for?('osdeps_mode') && mode_name = ENV['AUTOPROJ_OSDEPS_MODE']
                        begin osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode given through AUTOPROJ_OSDEPS_MODE (#{mode})"
                            nil
                        end
                    else
                        mode_name = config.get('osdeps_mode')
                        begin osdeps_mode_string_to_value(mode_name)
                        rescue ArgumentError
                            Autoproj.warn "invalid osdeps mode stored in configuration file"
                            nil
                        end
                    end

                if mode
                    @osdeps_mode = mode
                    config.set('osdeps_mode', mode_name, true)
                    return mode
                end

                # Invalid configuration values. Retry
                config.reset('osdeps_mode')
                ENV['AUTOPROJ_OSDEPS_MODE'] = nil
            end
        end

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
        def setup_package_managers(osdeps_mode: self.osdeps_mode)
            os_package_manager.enabled = false
            package_managers.each_value do |handler|
                handler.enabled = false
            end
            osdeps_mode.each do |m|
                if m == 'os'
                    os_package_manager.enabled = true
                elsif pkg = package_managers[m]
                    pkg.enabled = true
                else
                    Autoproj.warn "osdep handler #{m.inspect} has no handler, available handlers are #{package_managers.keys.map(&:inspect).sort.join(", ")}"
                end
            end
            os_package_manager.silent = self.silent?
            package_managers.each_value do |v|
                v.silent = self.silent?
            end

            enabled_handlers = []
            if os_package_manager.enabled?
                enabled_handlers << os_package_manager
            end
            package_managers.each_value do |v|
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
            install(packages, options.merge(install_only: true))
            packages = os_package_resolver.resolve_os_packages(packages)

            packages = packages.map do |handler_name, list|
                if manager = package_managers[handler_name]
                    [package_managers[handler_name], list]
                else
                    raise ArgumentError, "no package manager called #{handler_name} found"
                end
            end

            _, other_packages =
                packages.partition { |handler, list| handler == os_package_manager }
            other_packages.each do |handler, list|
                if handler.respond_to?(:pristine)
                    handler.pristine(list)
                end
            end
        end

        # Requests the installation of the given set of packages
        def install(osdep_packages, install_only: false, **options)
            osdep_packages = osdep_packages.to_set - installed_packages
            return if osdep_packages.empty?

            setup_package_managers(**options)

            packages = os_package_resolver.resolve_os_packages(osdep_packages)
            packages = packages.map do |handler_name, list|
                if manager = package_managers[handler_name]
                    [package_managers[handler_name], list]
                else
                    raise ArgumentError, "no package manager called #{handler_name} found"
                end
            end

            # Install OS packages first, as the other package handlers might
            # depend on OS packages
            os_packages, other_packages = packages.partition do |handler, list|
                handler == os_package_manager
            end
            [os_packages, other_packages].each do |packages|
                packages.each do |handler, list|
                    list = list.to_set - installed_resolved_packages[handler]
                    next if list.empty?

                    handler.install(
                        list.to_a,
                        filter_uptodate_packages: filter_uptodate_packages?,
                        install_only: install_only)
                    installed_resolved_packages[handler].merge(list)
                end
            end
            installed_packages.merge(packages)
        end
    end
end 

