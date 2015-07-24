require 'autoproj/cli/inspection_tool'
module Autoproj
    module CLI
        class Envsh < InspectionTool
            def validate_options(_unused, options = Hash.new)
                _, options = super(_unused, options)
                options
            end

            def run(options = Hash.new)
                initialize_and_load
                finalize_setup(Array.new,
                    ignore_non_imported_packages: true)

                options = Kernel.validate_options options,
                    shell_helpers: ws.config.shell_helpers?
                ws.export_env_sh(shell_helpers: options[:shell_helpers])
            end
        end
    end
end

