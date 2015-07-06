module Autoproj
    class ConfigError < RuntimeError
        attr_accessor :file
        def initialize(file = nil)
            super
            @file = file
        end
    end
    class InternalError < RuntimeError; end

    # Exception raised when trying to resolve a package name and it failed
    class PackageNotFound < ConfigError
    end

    class InputError < RuntimeError; end

    # Exception raised when a caller requires to use an excluded package
    class ExcludedPackage < ConfigError
        attr_reader :name
        def initialize(name)
            @name = name
        end
    end

    # Exception raised when an unknown package is encountered
    class UnknownPackage < ConfigError
        attr_reader :name
        def initialize(name)
            @name = name
        end
    end

    class MissingOSDep < ConfigError; end

    # Exception raised by
    # PackageSelection#filter_excluded_and_ignored_packages when a given
    # selection is completely excluded
    class ExcludedSelection < ConfigError
        attr_reader :selection
        def initialize(selection)
            @selection = selection
        end
    end

    class UserError < RuntimeError; end

    class WorkspaceAlreadyCreated < RuntimeError; end
end


