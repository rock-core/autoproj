module Autoproj
    module PackageManagers
        # Base class for all package managers. Subclasses must add the
        # #install(packages) method and may add the
        # #filter_uptodate_packages(packages) method
        #
        # Package managers must be registered in PACKAGE_HANDLERS and
        # (if applicable) OS_PACKAGE_HANDLERS.
        class Manager
            # @return [Workspace] the workspace
            attr_reader :ws

            attr_writer :enabled
            def enabled?; !!@enabled end

            attr_writer :silent
            def silent?; !!@silent end

            # Whether this package manager should be called even if no packages
            # should be installed
            #
            # This is needed if the installer has ways to get specifications of
            # packages to install through other means than the osdep system, as
            # e.g. {BundlerManager} that would install gems listed in
            # autoproj/Gemfile
            def call_while_empty?
                false
            end

            # Whether this package manager needs to maintain a list of all the
            # packages that are needed for the whole installation (true), or
            # needs only to be called with packages to install
            #
            # OS package managers are generally non-strict (once a package is
            # installed, it's available to all). Package managers like
            # {BundlerManager} are strict as they maintain a list of gems that
            # are then made available to the whole installation
            #
            # The default is false, reimplement in subclasses to return true
            def strict?
                false
            end

            # Create a package manager
            #
            # @param [Workspace] ws the underlying workspace
            def initialize(ws)
                @ws = ws
                @enabled = true
                @silent = true
            end

            # Overload to perform initialization of environment variables in
            # order to have a properly functioning package manager
            #
            # This is e.g. needed for python pip or rubygems
            def initialize_environment
            end
        end
    end
end

