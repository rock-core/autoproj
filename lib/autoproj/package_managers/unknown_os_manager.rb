module Autoproj
    module PackageManagers
        # Dummy package manager used for unknown OSes. It simply displays a
        # message to the user when packages are needed
        class UnknownOSManager < Manager
            def initialize(ws)
                super(ws)
                @installed_osdeps = Set.new
            end

            def osdeps_interaction_unknown_os(osdeps)
                puts <<-EOMSG
  #{Autoproj.color("The build process requires some other software packages to be installed on our operating system", :bold)}
  #{Autoproj.color("If they are already installed, simply ignore this message", :red)}

    #{osdeps.to_a.sort.join("\n    ")}

                EOMSG
                print Autoproj.color("Press ENTER to continue", :bold)
                STDOUT.flush
                STDIN.readline
                puts
                nil
            end

            def install(osdeps)
                if silent?
                    return false
                else
                    osdeps = osdeps.to_set
                    osdeps -= @installed_osdeps
                    if !osdeps.empty?
                        result = osdeps_interaction_unknown_os(osdeps)
                    end
                    @installed_osdeps |= osdeps
                    return result
                end
            end
        end
    end
end

