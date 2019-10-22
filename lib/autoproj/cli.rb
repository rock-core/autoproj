module Autoproj
    module CLI
        class CLIException < RuntimeError
            def fatal?
                true
            end
        end
        class CLIInvalidArguments < CLIException
        end
        class CLIAmbiguousArguments < CLIException
        end
        class CLIInvalidSelection < CLIException
        end

        def self.load_plugins
            require 'autoproj/find_workspace'
            _, config = Autoproj.find_v2_workspace_config(Autoproj.default_find_base_dir)
            return unless config

            (config['plugins'] || {}).each_key do |plugin_name|
                require "#{plugin_name}" if plugin_name.start_with?('autoproj-')
            end
        end
    end
end
