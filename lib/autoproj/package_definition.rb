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
        def setup?; !!@setup end

        # Sets the {setup?} flag
        attr_writer :setup

        # @return [VCSDefinition] the version control information associated
        #   with this package
        attr_accessor :vcs

        def initialize(autobuild, package_set, file)
            @autobuild, @package_set, @file =
                autobuild, package_set, file
            @user_blocks = []
            @modes = ['import', 'build']
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
            @modes + autobuild.utilities.values.
                find_all { |u| u.enabled? }.
                map(&:name)
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
            if setup?
                block.call(autobuild)
            end
        end
    end
end
