module Autoproj
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
            def self.initialize_environment(_env = nil, _manifest = nil, _root_dir = Autoproj.root_dir)
            end
        end
    end
end

