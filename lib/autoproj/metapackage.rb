module Autoproj
    # A set of packages that can be referred to by name
    class Metapackage
        # The metapackage name
        attr_reader :name
        # The packages listed in this metapackage
        attr_reader :packages
        # The normal dependency handling behaviour is to generate an error if a
        # metapackage is selected for the build but some of its dependencies
        # cannot be built. This modifies the behaviour to simply ignore the
        # problematic packages.
        attr_writer :weak_dependencies

        # @return [Boolean] whether the dependencies from this metapackage are
        #   weak or not
        # @see #weak_dependencies
        def weak_dependencies?
            !!@weak_dependencies
        end

        def initialize(name)
            @name = name
            @packages = []
            @weak_dependencies = false
        end

        def size
            packages.size
        end

        # Adds a package to this metapackage
        #
        # @param [Autobuild::Package] pkg
        def add(pkg)
            @packages << pkg
        end

        # Lists the packages contained in this metapackage
        #
        # @yieldparam [Autobuild::Package] pkg
        def each_package(&block)
            @packages.each(&block)
        end

        # Tests if the given package is included in this metapackage
        #
        # @param [String,#name] pkg the package or package name
        def include?(pkg)
            if !pkg.respond_to?(:to_str)
                pkg = pkg.name
            end
            @packages.any? { |p| p.name == pkg }
        end
    end
end
