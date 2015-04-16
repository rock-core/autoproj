require 'autoproj/cli/inspection_tool'
module Autoproj
    module CLI
        class Envsh < InspectionTool
            def validate_options(options)
                handle_common_options(options)
                options
            end

            def run(options = Hash.new)
                finalize_setup
                options = Kernel.validate_options options,
                    shell_helpers: ws.config.shell_helpers?
                ws.env.export_env_sh(shell_helpers: options[:shell_helpers])
            end
        end
    end
end

