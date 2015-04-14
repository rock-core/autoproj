module Autoproj
    module CLI
        class Reconfigure
            attr_reader :ws

            def initialize(ws = Workspace.from_environment)
                @ws = ws
            end

            def run
                ws.setup
                ws.config.reconfigure!
                ws.load_package_sets
                ws.setup_all_package_directories
                ws.finalize_package_setup
                ws.config.save
            end
        end
    end
end

