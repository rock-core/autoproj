module Autoproj
    module RepositoryManagers
        # Base class for all repository managers. Subclasses must add the
        # #install(entries) method
        #
        # Repository managers must be registered in OS_REPOSITORY_MANAGERS
        class Manager
            # @return [Workspace] the workspace
            attr_reader :ws

            # Create a repository manager
            #
            # @param [Workspace] ws the underlying workspace
            def initialize(ws)
                @ws = ws
            end

            def install(definitions)
            end

            def os_dependencies
                []
            end
        end
    end
end
