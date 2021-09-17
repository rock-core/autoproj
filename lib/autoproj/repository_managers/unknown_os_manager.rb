module Autoproj
    module RepositoryManagers
        # Dummy repository manager used for unknown OSes. It simply displays a
        # message to the user when repositories are needed
        class UnknownOSManager < Manager
            def initialize(ws)
                @installed_osrepos = Set.new
                super(ws)
            end

            def osrepos_interaction_unknown_os
                Autoproj.message "The build process requires some repositories to be added on our operating system", :bold
                Autoproj.message "If they are already added, simply ignore this message", :bold
                Autoproj.message "Press ENTER to continue ", :bold

                STDIN.readline
                nil
            end

            def install(osrepos)
                super
                osrepos = osrepos.to_set
                osrepos -= @installed_osrepos
                result = osrepos_interaction_unknown_os unless osrepos.empty?
                @installed_osrepos |= osrepos
                result
            end
        end
    end
end
