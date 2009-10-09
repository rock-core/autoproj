module Rubotics
    BASE_DIR     = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))

    class UserError < RuntimeError; end

    def self.root_dir
        dir = Dir.pwd
        while dir != "/" && !File.directory?(File.join(dir, "rubotics"))
            dir = File.dirname(dir)
        end
        if dir == "/"
            raise UserError, "not in a Rubotics installation"
        end
        dir
    end

    def self.config_dir
        File.join(root_dir, "rubotics")
    end
    def self.build_dir
	File.join(root_dir, "build")
    end

    def self.config_file(file)
        File.join(config_dir, file)
    end

    def self.run_as_user(*args)
        if !system(*args)
            raise "failed to run #{args.join(" ")}"
        end
    end

    def self.run_as_root(*args)
        if !system('sudo', *args)
            raise "failed to run #{args.join(" ")} as root"
        end
    end

    def self.set_initial_env
        gem_home = File.join(Rubotics.config_dir, "gems")
        Rubotics.env_set 'RUBYOPT', "-rubygems"
        Rubotics.env_set 'GEM_HOME', gem_home
        Rubotics.env_set_path 'PATH', "#{gem_home}/bin", "/usr/local/bin", "/usr/bin", "/bin"
        Rubotics.env_set 'PKG_CONFIG_PATH'
        Rubotics.env_set 'RUBYLIB'
        Rubotics.env_inherit 'PATH', 'PKG_CONFIG_PATH', 'RUBYLIB'
    end

    def self.export_env_sh(subdir)
        File.open(File.join(Rubotics.root_dir, subdir, "env.sh"), "w") do |io|
            Autobuild.environment.each do |name, value|
                shell_line = "export #{name}=#{value.join(":")}"
                if Rubotics.env_inherit?(name)
                    if value.empty?
                        next
                    else
                        shell_line << ":$#{name}"
                    end
                end
                io.puts shell_line
            end
        end
    end
end

