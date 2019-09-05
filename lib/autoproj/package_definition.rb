module Autoproj
    # Autoproj-specific information about a package definition
    #
    # This stores the information that goes in addition to the autobuild package
    # definitions
    class PackageDefinition
        # @return [Autobuild::Package] the autobuild package definitins
        attr_reader :autobuild
        # @return [Array<#call>] the set of blocks that should be called to
        #   prepare the package. These are called before any operation has been
        #   performed on the package iself.
        attr_reader :user_blocks
        # @return [PackageSet] the package set that defined this package
        attr_reader :package_set
        # @return [String] path to the file that contains this package's
        #   definition
        attr_reader :file
        # Whether this package is completely setup
        #
        # If the package is set up, its importer as well as all target
        # directories are properly set, and all {user_blocks} have been called.
        def setup?
            @setup
        end

        # Sets the {setup?} flag
        attr_writer :setup

        # @return [VCSDefinition] the version control information associated
        #   with this package
        attr_accessor :vcs

        def initialize(autobuild, package_set, file)
            @autobuild = autobuild
            @package_set = package_set
            @file = file
            @user_blocks = []
            @modes = %w[import build]
            @setup = false
            @vcs = VCSDefinition.none
        end

        # The modes in which this package will be used
        #
        # Mainly used during dependency resolution to disable unneeded
        # dependencies
        #
        # @return [Array<String>]
        def modes
            @modes + autobuild.utilities
                     .values.find_all(&:enabled?).map(&:name)
        end

        # The package name
        # @return [String]
        def name
            autobuild.name
        end

        # Registers a setup block
        #
        # The block will be called when the setup phase is finished, or
        # immediately if it is already finished (i.e. if {setup?} returns true)
        #
        # @param [#call] block the block that should be registered
        # @yieldparam [Autobuild::Package] pkg the autobuild package object
        # @see {user_blocks}
        def add_setup_block(block)
            user_blocks << block
            block.call(autobuild) if setup?
        end

        # Whether this package is already checked out
        def checked_out?
            autobuild.checked_out?
        end

        # Add another package as a dependency of this one
        def depends_on(pkg)
            autobuild.depends_on(pkg.autobuild)
        end

        def apply_dependencies_from_manifest
            manifest = autobuild.description
            manifest.each_dependency(modes) do |name, is_optional|
                begin
                    if is_optional
                        autobuild.optional_dependency name
                    else
                        autobuild.depends_on name
                    end
                rescue ConfigError => e
                    raise ConfigError.new(manifest.path),
                          "manifest #{manifest.path} of #{self.name} from "\
                          "#{package_set.name} lists '#{name}' as dependency, "\
                          'but it is neither a normal package nor an osdeps '\
                          "package. osdeps reports: #{e.message}", e.backtrace
                end
            end
        end
    end
end
