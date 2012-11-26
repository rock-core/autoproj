module Autoproj
    class UserError < RuntimeError; end

    # OS-independent creation of symbolic links. Note that on windows, it only
    # works for directories
    def create_symlink(from, to)
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

    # Returns the root directory of the current autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.root_dir(dir = Dir.pwd)
        if @root_dir
            return @root_dir
        end

        root_dir_rx =
            if Autobuild.windows? then /^[a-zA-Z]:\\\\$/
            else /^\/$/
            end

        while root_dir_rx !~ dir && !File.directory?(File.join(dir, "autoproj"))
            dir = File.dirname(dir)
        end
        if root_dir_rx =~ dir
            raise UserError, "not in a Autoproj installation"
        end

        #Preventing backslashed in path, that might be confusing on some path compares
        if Autobuild.windows?
            dir = dir.gsub(/\\/,'/')
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
        ENV['AUTOPROJ_GEM_HOME'] || File.join(root_dir, ".gems")
    end

    def self.env_inherit(*names)
        Autobuild.env_inherit(*names)
    end

    # Find the given program in PATH. It raises ArgumentError if the program
    # can't be found
    def self.find_in_path(name)
        result = ENV['PATH'].split(':').find { |dir| File.file?(File.join(dir, name)) }
        if !result
            raise ArgumentError, "#{name} can not be found in PATH (#{ENV['PATH']})"
        end
        File.join(result, name)
    end

    # Initializes the environment variables to a "sane default"
    #
    # Use this in autoproj/init.rb to make sure that the environment will not
    # get polluted during the build.
    def self.set_initial_env
        Autobuild.env_inherit = false
        Autoproj.env_set 'RUBYOPT', "-rubygems"
        Autobuild.env_push_path 'GEM_PATH', Autoproj.gem_home
        Autobuild.env_push_path 'PATH', "#{Autoproj.gem_home}/bin", "/usr/local/bin", "/usr/bin", "/bin"
    end

    class << self
        attr_writer :shell_helpers
        def shell_helpers?; !!@shell_helpers end
    end
    @shell_helpers = true

    # Create the env.sh script in +subdir+. In general, +subdir+ should be nil.
    def self.export_env_sh(subdir = nil)
        # Make sure that we have the environment of all selected packages
        if Autoproj.manifest # we don't have a manifest if we are bootstrapping
            Autoproj.manifest.all_selected_packages.each do |pkg_name|
                Autobuild::Package[pkg_name].update_environment
            end
        end

        filename = if subdir
               File.join(Autoproj.root_dir, subdir, ENV_FILENAME)
           else
               File.join(Autoproj.root_dir, ENV_FILENAME)
           end

        shell_dir = File.expand_path(File.join("..", "..", "shell"), File.dirname(__FILE__))
        if Autoproj.shell_helpers? && shell = ENV['SHELL']
            shell_kind = File.basename(shell)
            if shell_kind =~ /^\w+$/
                shell_file = File.join(shell_dir, "autoproj_#{shell_kind}")
                if File.exists?(shell_file)
                    Autoproj.message
                    Autoproj.message "autodetected the shell to be #{shell_kind}, sourcing autoproj shell helpers"
                    Autoproj.message "add \"Autoproj.shell_helpers = false\" in autoproj/init.rb to disable"
                    Autobuild.env_source_after(shell_file)
                end
            end
        end

        File.open(filename, "w") do |io|
            Autobuild.export_env_sh(io)
        end
    end

    # Load a definition file given at +path+. +source+ is the package set from
    # which the file is taken.
    #
    # If any error is detected, the backtrace will be filtered so that it is
    # easier to understand by the user. Moreover, if +source+ is non-nil, the
    # package set name will be mentionned.
    def self.load(package_set, *path)
        path = File.join(*path)
        in_package_set(package_set, File.expand_path(path).gsub(/^#{Regexp.quote(Autoproj.root_dir)}\//, '')) do
            begin
                Kernel.load path
            rescue Interrupt
                raise
            rescue ConfigError => e
                raise
            rescue Exception => e
                filter_load_exception(e, package_set, path)
            end
        end
    end

    # Same as #load, but runs only if the file exists.
    def self.load_if_present(package_set, *path)
        path = File.join(*path)
        if File.file?(path)
            self.load(package_set, *path)
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
                Autoproj.message("  WARN: #{name} has undefined symbols", :magenta)
            end
        end
    end
end

