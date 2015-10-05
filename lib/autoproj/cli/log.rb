require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Log < Base
            def run(args, options = Hash.new)
                ws = Workspace.from_environment
                ws.load_config

                if !ws.config.import_log_enabled?
                    Autoproj.error "import log is disabled on this install"
                    return
                elsif !Ops::Snapshot.update_log_available?(ws.manifest)
                    Autoproj.error "import log is not available on this install, the main build configuration repository is not using git"
                    return
                end

                exec(Autobuild.tool(:git), "--git-dir=#{ws.config_dir}/.git", 'reflog',
                     Ops::Snapshot.import_state_log_ref, '--format=%Cgreen%gd %Cblue%cr %Creset%gs',
                     *args)
            end
        end
    end
end

