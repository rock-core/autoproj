require 'autoproj/cli/base'

module Autoproj
    module CLI
        class Log < Base
            def run(args, options = Hash.new)
                ws.load_config

                if !ws.config.import_log_enabled?
                    Autoproj.error "import log is disabled on this install"
                    return
                elsif !Ops::Snapshot.update_log_available?(ws.manifest)
                    Autoproj.error "import log is not available on this install, the main build configuration repository is not using git"
                    return
                end

                common_args = [Autobuild.tool(:git), "--git-dir=#{ws.config_dir}/.git"]
                if since = options[:since]
                    exec(*common_args, 'diff', parse_log_entry(since), 'autoproj@{0}')
                elsif args.empty?
                    exec(*common_args, 'reflog',
                        Ops::Snapshot.import_state_log_ref, '--format=%Cgreen%gd %Cblue%cr %Creset%gs')
                elsif options[:diff]
                    exec(*common_args, 'diff', *args.map { |entry| parse_log_entry(entry) })
                else
                    exec(*common_args, 'show', *args.map { |entry| parse_log_entry(entry) })
                end
            end

            def parse_log_entry(entry)
                if entry =~ /^autoproj@{\d+}$/
                    entry
                elsif entry =~ /^\d+$/
                    "autoproj@{#{entry}}"
                else
                    raise CLIInvalidArguments, "unexpected revision name '#{entry}', expected either autoproj@{ID} or ID ('ID' being a number). Run 'autoproj log' without arguments for a list of known entries"
                end
            end
        end
    end
end
