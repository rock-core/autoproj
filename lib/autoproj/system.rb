module Autoproj
    BASE_DIR     = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))

    class UserError < RuntimeError; end

    def self.root_dir
        dir = Dir.pwd
        while dir != "/" && !File.directory?(File.join(dir, "autoproj"))
            dir = File.dirname(dir)
        end
        if dir == "/"
            raise UserError, "not in a Autoproj installation"
        end
        dir
    end

    def self.config_dir
        File.join(root_dir, "autoproj")
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

    def self.remotes_dir
        File.join(root_dir, ".remotes")
    end
    def self.gem_home
        File.join(root_dir, ".gems")
    end

    def self.set_initial_env
        Autoproj.env_set 'RUBYOPT', "-rubygems"
        Autoproj.env_set 'GEM_HOME', Autoproj.gem_home
        Autoproj.env_set_path 'PATH', "#{Autoproj.gem_home}/bin", "/usr/local/bin", "/usr/bin", "/bin"
        Autoproj.env_set 'PKG_CONFIG_PATH'
        Autoproj.env_set 'RUBYLIB'
        Autoproj.env_set 'LD_LIBRARY_PATH'
    end

    def self.export_env_sh(subdir = nil)
        filename = if subdir
                       File.join(Autoproj.root_dir, subdir, "env.sh")
                   else
                       File.join(Autoproj.root_dir, "env.sh")
                   end

        File.open(filename, "w") do |io|
            Autobuild.environment.each do |name, value|
                shell_line = "export #{name}=#{value.join(":")}"
                if Autoproj.env_inherit?(name)
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

    def self.load(source, *path)
        path = File.join(*path)
        Kernel.load path
    rescue Exception => e
        Autoproj.filter_load_exception(e, source, path)
    end

    def self.load_if_present(source, *path)
        path = File.join(*path)
        if File.file?(path)
            self.load(source, *path)
        end
    end

    def self.validate_solib_dependencies(dir, exclude_paths = [])
        Find.find(File.expand_path(dir)) do |name|
            next unless name =~ /\.so$/
            next if exclude_paths.find { |p| name =~ p }

            output = `ldd -r #{name} 2>&1`
            if output =~ /undefined symbol/
                STDERR.puts Autoproj.console.color("WARN: #{name} has undefined symbols", :magenta)
            end
        end
    end
end

