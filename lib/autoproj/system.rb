module Autoproj
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
        !!find_workspace_dir(path, 'workspace')
    end

    # Forcefully sets the root directory
    #
    # This is mostly useful during bootstrapping (i.e. when the search would
    # fail)
    def self.root_dir=(dir)
        if @workspace && dir != @workspace.root_dir
            raise WorkspaceAlreadyCreated, "cannot switch global root directory after a workspace object got created"
        end
        @root_dir = dir
    end

    # Returns the root directory of the current autoproj installation.
    #
    # If the current directory is not in an autoproj installation,
    # raises UserError.
    def self.root_dir(dir = Dir.pwd)
        if @root_dir
            return @root_dir
        elsif !dir
            @root_dir = ni
            return
        end
        path = Autoproj.find_workspace_dir(dir)
        if !path
            raise UserError, "not in a Autoproj installation"
        end
        path
    end

    # @deprecated use workspace.config_dir instead
    def self.config_dir
        Autoproj.warn "#{__method__} is deprecated, use workspace.config_dir instead"
        caller.each { |l| Autoproj.warn "  #{l}" }
        workspace.config_dir
    end
    # @deprecated use workspace.overrides_dir instead
    def self.overrides_dir
        Autoproj.warn "#{__method__} is deprecated, use workspace.overrides_dir instead"
        caller.each { |l| Autoproj.warn "  #{l}" }
        workspace.overrides_dir
    end
    # @deprecated use Autobuild.find_in_path instead
    #
    # Warning: the autobuild method returns nil (instead of raising) if the
    # argument cannot be found
    def self.find_in_path(name)
        Autoproj.warn "#{__method__} is deprecated, use Autobuild.find_in_path instead"
        caller.each { |l| Autoproj.warn "  #{l}" }
        if path = Autobuild.find_in_path(name)
            return path
        else raise ArgumentError, "cannot find #{name} in PATH (#{ENV['PATH']})"
        end
    end
    # @deprecated use workspace.prefix_dir instead
    def self.prefix
        Autoproj.warn_deprecated(__method__, 'workspace.prefix_dir')
        workspace.prefix_dir
    end
    # @deprecated use workspace.prefix_dir= instead
    def self.prefix=(path)
        Autoproj.warn_deprecated(__method__, 'workspace.prefix_dir=')
        workspace.prefix_dir = path
    end
    # @deprecated use workspace.prefix_dir instead
    def self.build_dir
        Autoproj.warn_deprecated(__method__, 'workspace.prefix_dir')
        workspace.prefix_dir
    end
    # @deprecated compute the full path with File.join(config_dir, file)
    #   directly instead
    def self.config_file(file)
        Autoproj.warn_deprecated(__method__, 'compute the full path with File.join(config_dir, ...) instead')
        File.join(config_dir, file)
    end
    # @deprecated use workspace.remotes_dir instead
    def self.remotes_dir
        Autoproj.warn_deprecated(__method__, 'use workspace.remotes_dir instead')
        workspace.remotes_dir
    end
    # @deprecated use workspace.load or add a separate Loader object to your class
    def self.load(package_set, *path)
        Autoproj.warn_deprecated(
            __method__,
            'use workspace.load or add a separate Loader object to your class')
        workspace.load(package_set, *path)
    end
    # @deprecated use workspace.load_if_present or add a separate Loader object to your class
    def self.load_if_present(package_set, *path)
        Autoproj.warn_deprecated(
            __method__,
            'use workspace.load_if_present or add a separate Loader object to your class')
        workspace.load_if_present(package_set, *path)
    end

    # Run the provided command as user
    def self.run_as_user(*args)
        if !system(*args)
            raise "failed to run #{args.join(" ")}"
        end
    end
    # Run the provided command as root, using sudo to gain root access
    def self.run_as_root(*args, env: self.workspace.env)
        if !system(Autobuild.tool_in_path('sudo', env: env), *args)
            raise "failed to run #{args.join(" ")} as root"
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

