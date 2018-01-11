module Autoproj
    class ConfigError < RuntimeError
        attr_accessor :file
        def initialize(file = nil)
            super
            @file = file
        end
    end
    class InternalError < RuntimeError; end

    class ImportFailed < Autobuild::CompositeException
        def empty?
            original_errors.empty?
        end
    end

    class PackageImportFailed < ImportFailed
        # The list of the source packages that have been updated
        attr_reader :source_packages
        # The list of osdep packages that should be installed because of
        # {#source_packages}
        attr_reader :osdep_packages

        def initialize(original_errors, source_packages: [], osdep_packages: [])
            super(original_errors)
            @source_packages = source_packages
            @osdep_packages = osdep_packages
        end
    end

    # Exception raised when trying to resolve a package name and it failed
    class PackageNotFound < ConfigError; end

    class PackageUnavailable < PackageNotFound; end

    class UnregisteredPackage < ArgumentError
    end

    class UnregisteredPackageSet < ArgumentError
    end

    class InvalidPackageManifest < RuntimeError; end

    class InputError < RuntimeError; end

    # Exception raised when a caller requires to use an excluded package
    class ExcludedPackage < ConfigError
        attr_reader :name
        def initialize(name)
            @name = name
        end
    end

    class MissingOSDep < ConfigError; end

    # Exception raised when finding unexpected objects in a YAML file
    #
    # E.g. having a hash instead of an array
    class InvalidYAMLFormatting < ConfigError; end

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

    class InvalidWorkspace < RuntimeError; end

    class WorkspaceAlreadyCreated < InvalidWorkspace; end

    # Exception raised when looking for a workspace and it cannot be found
    class NotWorkspace < InvalidWorkspace; end

    # Exception raised when the autoproj workspace changes and the current
    # workspace is outdated
    class OutdatedWorkspace < InvalidWorkspace; end

    # Exception raised when initializing on a workspace that is not the current
    # one
    class MismatchingWorkspace < InvalidWorkspace; end
end


