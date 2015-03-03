module Autoproj
    class UserError < RuntimeError; end

    # OS-independent creation of symbolic links. Note that on windows, it only
    # works for directories
    def self.create_symlink(from, to)
        if Autobuild.windows?
            Dir.create_junction(to, from)
        else
            FileUtils.ln_sf from, to
        end
    end

    # Returns true if +path+ is part of an autoproj installation
    def self.in_autoproj_installation?(path)
        root_dir(File.expand_path(path))
        true
    rescue UserError
        false
    end

    # Forcefully sets the root directory
    #
    # This is mostly useful during bootstrapping (i.e. when the search would
    # fail)
    def self.root_dir=(dir)
        @root_dir = dir
    end

    # Returns the root directory of the current autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.root_dir(dir = Dir.pwd)
        if @root_dir
            return @root_dir
        end

        path = Pathname.pwd
        while !path.root?
            if (path + "autoproj" + 'manifest').file?
                break
            end
            path = path.parent
        end

        if path.root?
            raise UserError, "not in a Autoproj installation"
        end

        result = path.to_s
        # I don't know if this is still useful or not ... but it does not hurt
        #
        # Preventing backslashed in path, that might be confusing on some path compares
        if Autobuild.windows?
            result = result.gsub(/\\/,'/')
        end
        result
    end

    # Returns the configuration directory for this autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.config_dir
        File.join(root_dir, "autoproj")
    end

    OVERRIDES_DIR = "overrides.d"

    # Returns the directory containing overrides files
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.overrides_dir
        File.join(config_dir, OVERRIDES_DIR)
    end

    # @deprecated use Autobuild.find_in_path instead
    #
    # Warning: the autobuild method returns nil (instead of raising) if the
    # argument cannot be found
    def self.find_in_path(name)
        if path = Autobuild.find_in_path(name)
            return path
        else raise ArgumentError, "cannot find #{name} in PATH (#{ENV['PATH']})"
        end
    end

    class << self
        # The directory in which packages will be installed.
        #
        # If it is a relative path, it is relative to the root dir of the
        # installation.
        #
        # The default is "install"
        attr_reader :prefix

        # Change the value of 'prefix'
        def prefix=(new_path)
            @prefix = new_path
            Autoproj.change_option('prefix', new_path, true)
        end
    end
    @prefix = "install"

    # Returns the build directory (prefix) for this autoproj installation.
    #
    # If the current directory is not in an autoproj installation, raises
    # UserError.
    def self.build_dir
        File.expand_path(Autoproj.prefix, root_dir)
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
        if !system(Autobuild.tool_in_path('sudo'), *args)
            raise "failed to run #{args.join(" ")} as root"
        end
    end

    # Return the directory in which remote package set definition should be
    # checked out
    def self.remotes_dir
        File.join(root_dir, ".remotes")
    end


    def self.env_inherit(*names)
        Autobuild.env_inherit(*names)
    end

    # @deprecated use isolate_environment instead
    def self.set_initial_env
        isolate_environment
    end

    # Initializes the environment variables to a "sane default"
    #
    # Use this in autoproj/init.rb to make sure that the environment will not
    # get polluted during the build.
    def self.isolate_environment
        Autobuild.env_inherit = false
        Autobuild.env_push_path 'PATH', "/usr/local/bin", "/usr/bin", "/bin"
    end

    def self.prepare_environment
        # Set up some important autobuild parameters
        env_inherit 'PATH', 'PKG_CONFIG_PATH', 'RUBYLIB', \
            'LD_LIBRARY_PATH', 'CMAKE_PREFIX_PATH', 'PYTHONPATH'
        
        env_set 'AUTOPROJ_CURRENT_ROOT', Autoproj.root_dir
        env_set 'RUBYOPT', "-rubygems"
        Autoproj::OSDependencies::PACKAGE_HANDLERS.each do |pkg_mng|
            pkg_mng.initialize_environment
        end
    end

    class << self
        attr_writer :shell_helpers
        def shell_helpers?; !!@shell_helpers end
    end
    @shell_helpers = true

    # Create the env.sh script in +subdir+. In general, +subdir+ should be nil.
    def self.export_env_sh(subdir = nil)
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
            Autobuild.env_source_after(File.join(shell_dir, "autoproj_sh"))
        end

        File.open(filename, "w") do |io|
            if Autobuild.env_inherit
                io.write <<-EOF
                if test -n "$AUTOPROJ_CURRENT_ROOT" && test "$AUTOPROJ_CURRENT_ROOT" != "#{Autoproj.root_dir}"; then
                    echo "the env.sh from $AUTOPROJ_CURRENT_ROOT is already loaded. Start a new shell before sourcing this one"
                    return
                fi
                EOF
            end
            Autobuild.export_env_sh(io)
        end
    end

    # @deprecated use Ops.loader.load or add a proper Loader object to your
    #   class
    def self.load(package_set, *path)
        Ops.loader.load(package_set, *path)
    end

    # @deprecated use Ops.loader.load_if_present or add a proper Loader object
    #   to your class
    def self.load_if_present(package_set, *path)
        Ops.loader.load_if_present(package_set, *path)
    end

    # Look into +dir+, searching for shared libraries. For each library, display
    # a warning message if this library has undefined symbols.
    def self.validate_solib_dependencies(dir, exclude_paths = [])
        Find.find(File.expand_path(dir)) do |name|
            next unless name =~ /\.so$/
            next if exclude_paths.find { |p| name =~ p }

            output = `ldd -r #{name} 2>&1`
            if output =~ /undefined symbol/
                Autoproj.message("  WARN: #{name} has undefined symbols", :magenta)
            end
        end
    end
end

