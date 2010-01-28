module Autoproj
    BASE_DIR     = File.expand_path(File.join('..', '..'), File.dirname(__FILE__))

    class UserError < RuntimeError; end

    # Returns the root directory of the current autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
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

    # Returns the configuration directory for this autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.config_dir
        File.join(root_dir, "autoproj")
    end

    # Returns the build directory (prefix) for this autoproj installation.
    #
    # If the current directory is not in an autoproj installation, raises
    # UserError.
    def self.build_dir
	File.join(root_dir, "build")
    end

    # Returns the path to the provided configuration file.
    #
    # If the current directory is not in an autoproj installation, raises
    # UserError.
    def self.config_file(file)
        File.join(config_dir, file)
    end

    # Run the provided command as user
    def self.run_as_user(*args)
        if !system(*args)
            raise "failed to run #{args.join(" ")}"
        end
    end

    # Run the provided command as root, using sudo to gain root access
    def self.run_as_root(*args)
        if !system('sudo', *args)
            raise "failed to run #{args.join(" ")} as root"
        end
    end

    # Return the directory in which remote package set definition should be
    # checked out
    def self.remotes_dir
        File.join(root_dir, ".remotes")
    end

    # Return the directory in which RubyGems package should be installed
    def self.gem_home
        File.join(root_dir, ".gems")
    end

    # Initializes the environment variables to a "sane default"
    #
    # Use this in autoproj/init.rb to make sure that the environment will not
    # get polluted during the build.
    def self.set_initial_env
        Autoproj.env_set 'RUBYOPT', "-rubygems"
        Autoproj.env_set 'GEM_HOME', Autoproj.gem_home
        Autoproj.env_set_path 'PATH', "#{Autoproj.gem_home}/bin", "/usr/local/bin", "/usr/bin", "/bin"
        Autoproj.env_set 'PKG_CONFIG_PATH'
        Autoproj.env_set 'RUBYLIB'
        Autoproj.env_set 'LD_LIBRARY_PATH'
    end

    # Create the env.sh script in +subdir+. In general, +subdir+ should be nil.
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

    # Load a definition file given at +path+. +source+ is the package set from
    # which the file is taken.
    #
    # If any error is detected, the backtrace will be filtered so that it is
    # easier to understand by the user. Moreover, if +source+ is non-nil, the
    # package set name will be mentionned.
    def self.load(source, *path)
        path = File.join(*path)
        Kernel.load path
    rescue Exception => e
        Autoproj.filter_load_exception(e, source, path)
    end

    # Same as #load, but runs only if the file exists.
    def self.load_if_present(source, *path)
        path = File.join(*path)
        if File.file?(path)
            self.load(source, *path)
        end
    end

    # Look into +dir+, searching for shared libraries. For each library, display
    # a warning message if this library has undefined symbols.
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

