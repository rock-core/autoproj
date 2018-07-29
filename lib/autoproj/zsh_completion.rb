require 'autoproj/shell_completion'

module Autoproj
    # This class generates shell completion for code for a given Thor subclasss
    class ZshCompletion < ShellCompletion
        MAIN_FUNCTION_TEMPLATE = 'main.zsh.erb'
        SUBCOMMAND_FUNCTION_TEMPLATE = 'subcommand.zsh.erb'

        def setup_file_completion(metadata)
            metadata[:completer] = '_files'
        end

        def setup_executable_completion(metadata)
            metadata[:completer] = '_path_commands'
        end

        def setup_package_completion(metadata)
            metadata[:completer] = '_autoproj_installed_packages'
        end

        def disable_completion(metadata)
            metadata[:completer] = ':'
        end

        def quote(s)
            escaped = s.gsub(/'/, "''")
            %('#{escaped}')
        end

        def bracket(s)
            %([#{s}])
        end

        def escape_option_names(names)
            if names.size == 1
                names.first
            else
                '{' + names.join(',') + '}'
            end
        end
    end
end

