module Autoproj
    # Class used to store information about a package definition
    class PackageDefinition
        attr_reader :autobuild
        attr_reader :user_blocks
        attr_reader :package_set
        attr_reader :file
        def setup?; !!@setup end
        attr_writer :setup
        attr_accessor :vcs

        def initialize(autobuild, package_set, file)
            @autobuild, @package_set, @file =
                autobuild, package_set, file
            @user_blocks = []
        end

        def name
            autobuild.name
        end

        def add_setup_block(block)
            user_blocks << block
            if setup?
                block.call(autobuild)
            end
        end
    end
end
