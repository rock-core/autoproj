require "pathname"
require "autoproj/exceptions"
require "autobuild/environment"

module Autoproj
    module Ops
        # Find the given executable file in PATH
        #
        # If `cmd` is an absolute path, it will either return it or raise if
        # `cmd` is not executable. Otherwise, looks for an executable named
        # `cmd` in PATH and returns it, or raises if it cannot be found. The
        # exception contains a more detailed reason for failure
        #
        #
        # @param [String] cmd
        # @return [String] the resolved program
        # @raise [ExecutableNotFound] if an executable file named `cmd` cannot
        #   be found
        def self.which(cmd, path_entries: nil)
            path = Pathname.new(cmd)
            if path.absolute?
                if path.file? && path.executable?
                    cmd
                elsif path.exist?
                    raise ExecutableNotFound.new(cmd),
                          "given command `#{cmd}` exists but is not an executable file"
                else
                    raise ExecutableNotFound.new(cmd),
                          "given command `#{cmd}` does not exist, "\
                          "an executable file was expected"
                end
            else
                path_entries = path_entries.call if path_entries.respond_to?(:call)
                absolute = Autobuild::Environment.find_executable_in_path(cmd, path_entries)

                if absolute
                    absolute
                elsif (file = Autobuild::Environment.find_in_path(cmd, path_entries))
                    raise ExecutableNotFound.new(cmd),
                          "`#{cmd}` resolves to #{file} which is not executable"
                else
                    raise ExecutableNotFound.new(cmd),
                          "cannot resolve `#{cmd}` to an executable in the workspace"
                end
            end
        end
    end
end
