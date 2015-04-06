module Autoproj
    class Environment < Autobuild::Environment
        def prepare(manifest = Autoproj.manifest)
            set 'AUTOPROJ_CURRENT_ROOT', Autoproj.root_dir
        end

        def expand(value)
            Autoproj.expand_environment(value)
        end

        def export_env_sh(subdir)
            # Make sure that we have as much environment as possible
            Autoproj::CmdLine.update_environment

            filename = if subdir
                   File.join(Autoproj.root_dir, subdir, ENV_FILENAME)
               else
                   File.join(Autoproj.root_dir, ENV_FILENAME)
               end

            shell_dir = File.expand_path(File.join("..", "..", "shell"), File.dirname(__FILE__))
            if Autoproj.shell_helpers?
                Autoproj.message "sourcing autoproj shell helpers"
                Autoproj.message "add \"Autoproj.shell_helpers = false\" in autoproj/init.rb to disable"
                source_after(File.join(shell_dir, "autoproj_sh"))
            end

            File.open(filename, "w") do |io|
                if inherit?
                    io.write <<-EOF
                    if test -n "$AUTOPROJ_CURRENT_ROOT" && test "$AUTOPROJ_CURRENT_ROOT" != "#{Autoproj.root_dir}"; then
                        echo "the env.sh from $AUTOPROJ_CURRENT_ROOT is already loaded. Start a new shell before sourcing this one"
                        return
                    fi
                    EOF
                end
                super(io)
            end
        end
    end

    def self.env
        if !@env
            @env = Environment.new
            @env.prepare
            Autobuild.env = @env
        end
        @env
    end

    # @deprecated call Autoproj.env.set instead
    def self.env_set(name, *value)
        Autoproj.env.set(name, *value)
    end
    # @deprecated call Autoproj.env.add instead
    def self.env_add(name, *value)
        Autoproj.env.add(name, *value)
    end
    # @deprecated call Autoproj.env.set_path instead
    def self.env_set_path(name, *value)
        Autoproj.env.set_path(name, *value)
    end
    # @deprecated call Autoproj.env.add_path instead
    def self.env_add_path(name, *value)
        Autoproj.env.add_path(name, *value)
    end
    # @deprecated call Autoproj.env.source_after instead
    def self.env_source_file(file)
        Autoproj.env.source_after(file)
    end
    # @deprecated call Autoproj.env.source_after instead
    def self.env_source_after(file)
        Autoproj.env.source_after(file)
    end
    # @deprecated call Autoproj.env.source_before instead
    def self.env_source_before(file)
        Autoproj.env.source_before(file)
    end
    # @deprecated call Autoproj.env.inherit instead
    def self.env_inherit(*names)
        Autoproj.env.inherit(*names)
    end
    # @deprecated use Autoproj.env.isolate instead
    def self.set_initial_env
        isolate_environment
    end
    # @deprecated use Autoproj.env.isolate instead
    def self.isolate_environment
        Autoproj.env.isolate
    end
    # @deprecated call Autoproj.env.prepare directly
    def self.prepare_environment(env = Autoproj.env, manifest = Autoproj.manifest)
        env.prepare(manifest)
    end
    # @deprecated use Autoproj.env.export_env_sh instead
    def self.export_env_sh(subdir = nil)
        Autoproj.env.export_env_sh(subdir)
    end
end
