require "autoproj/shell_completion"

module Autoproj
    # This class generates shell completion for code for a given Thor subclasss
    class BashCompletion < ShellCompletion
        MAIN_FUNCTION_TEMPLATE = "main.bash.erb"
        SUBCOMMAND_FUNCTION_TEMPLATE = "subcommand.bash.erb"

        def setup_file_completion(metadata)
            metadata[:completer] = "_filedir"
        end

        def setup_executable_completion(metadata)
            metadata[:completer] = 'COMPREPLY=( $( compgen -d -c -- "$cur" ) )'
        end

        def setup_package_completion(metadata)
            metadata[:completer] = "_autoproj_installed_packages"
        end

        def disable_completion(metadata)
            metadata[:completer] = nil
        end
    end
end
