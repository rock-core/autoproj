require "autoproj/cli/base"
module Autoproj
    module CLI
        class Reconfigure < Base
            def run(args, options = Hash.new)
                ws.setup
                ws.config.reconfigure!
                options.each do |k, v|
                    ws.config.set k, v, true
                end
                ws.load_package_sets
                ws.setup_all_package_directories
                ws.finalize_package_setup
                ws.config.save
            end
        end
    end
end
