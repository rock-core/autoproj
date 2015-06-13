require 'autoproj'
require 'autoproj/cli/base'
require 'autoproj/ops/main_config_switcher'
require 'autoproj/ops/configuration'

module Autoproj
    module CLI
        class SwitchConfig < Base
            def run(args, options = Hash.new)
                if Dir.pwd.start_with?(ws.remotes_dir) || Dir.pwd.start_with?(ws.config_dir)
                    raise ConfigError, "you cannot run autoproj switch-config from autoproj's configuration directory or one of its subdirectories"
                end

                # We must switch to the root dir first, as it is required by the
                # configuration switch code. This is acceptable as long as we
                # quit just after the switch
                switcher = Ops::MainConfigSwitcher.new(ws)
                if switcher.switch_config(*args)
                    manifest = Manifest.load(File.join(ws.config_dir, 'manifest'))
                    update = Ops::Configuration.new(ws, ws.loader)
                    update.update_configuration
                    ws.config.save
                end
            end
        end
    end
end

