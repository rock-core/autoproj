require "open3"
require "rubygems"

module Autoproj
    module Python
        # Get the python version for a given python executable
        # @return [String] The python version as <major>.<minor>
        def self.get_python_version(python_bin)
            unless File.exist?(python_bin)
                raise ArgumentError, "Autoproj::Python.get_python_version executable "\
                                     "'#{python_bin}' does not exist"
            end

            cmd = "#{python_bin} -c \"import sys;"\
                  "version=sys.version_info[:3]; "\
                  "print('{0}.{1}'.format(*version))\"".strip

            msg, status = Open3.capture2e(cmd)
            if status.success?
                msg.strip

            else
                raise "Autoproj::Python.get_python_version identification"\
                      " of python version for '#{python_bin}' failed: #{msg}"
            end
        end

        def self.get_pip_version(pip_bin)
            unless File.exist?(pip_bin)
                raise ArgumentError, "Autoproj::Python.get_pip_version executable "\
                                     "'#{pip_bin}' does not exist"
            end

            cmd = "#{pip_bin} --version"

            msg, status = Open3.capture2e(cmd)
            if status.success?
                msg.split(" ")[1]

            else
                raise "Autoproj::Python.get_pip_version identification"\
                      " of pip version for '#{pip_bin}' failed: #{msg}"
            end
        end

        def self.validate_version(version, version_constraint)
            if version_constraint
                dependency = Gem::Dependency.new("python", version_constraint)
                dependency.match?("python", version)
            else
                true
            end
        end

        # Validate that a given python executable's version fulfills
        # a given version constraint
        # @param [String] python_bin the python executable
        # @param [String] version_constraint version constraint, e.g., <3.8, >= 3.7, 3.6
        # @return [String,Bool] Version and validation result, i.e.,
        #         True if binary fulfills the version constraint, false otherwise
        def self.validate_python_version(python_bin, version_constraint)
            version = get_python_version(python_bin)
            [version, validate_version(version, version_constraint)]
        end

        # Find python given a version constraint
        # @return [String,String] path to python executable and python version
        def self.find_python(ws: Autoproj.workspace,
            version: ws.config.get("python_version", nil))
            finders = [
                -> { Autobuild.programs["python"] },
                -> { Autobuild.find_in_path("python3") },
                -> { Autobuild.find_in_path("python") }
            ]

            finders.each do |finder|
                if (python_bin = finder.call)
                    python_version, valid = validate_python_version(python_bin, version)
                    return python_bin, python_version if valid
                end
            end
            raise "Autoproj::Python.find_python_bin: failed to find python" \
                  " for version '#{version}'"
        end

        # Get information about the python executable from autoproj config,
        # but ensure the version constraint matches
        #
        # @return [String, String] Return path and version if the constraints
        #      are fulfilled nil otherwise

        def self.get_python_from_config(ws: Autoproj.workspace, version: nil)
            config_bin = ws.config.get("python_executable", nil)
            return unless config_bin

            config_version = ws.config.get("python_version", nil)
            config_version ||= get_python_version(config_bin)

            # If a version constraint is given, ensure fulfillment
            if validate_version(config_version, version)
                [config_bin, config_version]
            else
                raise "python_executable in autoproj config with " \
                      "version '#{config_version}' does not match "\
                      "version constraints '#{version}'"
            end
        end

        def self.custom_resolve_python(bin: nil,
            version: nil)
            version, valid = validate_python_version(bin, version)
            if valid
                [bin, version]
            else
                raise "Autoproj::Python.resolve_python: requested python"\
                      "executable '#{bin}' does not satisfy version"\
                      "constraints '#{version}'"
            end
        end

        def self.auto_resolve_python(ws: Autoproj.workspace,
            version: nil)
            version_constraint = version
            resolvers = [
                -> { get_python_from_config(ws: ws, version: version_constraint) },
                -> { find_python(ws: ws, version: version_constraint) }
            ]

            bin = nil
            resolvers.each do |resolver|
                bin, version = resolver.call
                if bin && File.exist?(bin) && version
                    Autoproj.debug "Autoproj::Python.resolve_python: " \
                                   "found python '#{bin}' version '#{version}'"
                    break
                end
            rescue RuntimeError => e
                Autoproj.debug "Autoproj::Python.resolve_python: " \
                               "resolver failed: #{e}"
            end

            unless bin
                msg = "Autoproj::Python.resolve_python: " \
                      "failed to find a python executable"
                if version_constraint
                    msg += " satisfying version constraint '#{version_constraint}'"
                end
                raise msg
            end
            [bin, version]
        end

        # Resolve the python executable according to a given version constraint
        # @param [Autoproj.workspace] ws Autoproj workspace
        # @param [String] bin Path to the python executable that shall be used,
        #   first fallback is the python_executable set in Autoproj's configuration,
        #   second fallback is a full search
        # @param [String] version version constraint
        # @return [String,String] python path and python version
        def self.resolve_python(ws: Autoproj.workspace,
            bin: nil,
            version: nil)
            if bin
                custom_resolve_python(bin: bin, version: version)
            else
                auto_resolve_python(ws: ws, version: version)
            end
        end

        def self.remove_python_shims(prefix_dir)
            shim_path = File.join(prefix_dir, "bin", "python")
            FileUtils.rm shim_path if File.exist?(shim_path)
        end

        def self.remove_pip_shims(prefix_dir)
            shim_path = File.join(prefix_dir, "bin", "pip")
            FileUtils.rm shim_path if File.exist?(shim_path)
        end

        # Write a shim script prefix_dir/bin/name that runs python_executable
        #
        # @param [Array<String>] args arguments inserted before the shim's arguments
        # @param [String,nil] missing_hint if set, the shim fails with this message
        #   when python_executable does not exist, instead of failing in exec
        # @return [String] the path to the shim
        def self.write_shim(name, python_executable, prefix_dir,
            args: [], missing_hint: nil)
            shim_path = File.join(prefix_dir, "bin")
            unless File.exist?(shim_path)
                FileUtils.mkdir_p shim_path
                Autoproj.warn "Autoproj::Python.write_shim: creating "\
                              "#{shim_path} - "\
                              "are you operating on a valid autoproj workspace?"
            end

            path = File.join(shim_path, name)
            File.open(path, "w") do |io|
                io.puts "#! /bin/sh"
                if missing_hint
                    io.puts "if [ ! -x \"#{python_executable}\" ]; then"
                    io.puts "    echo \"#{missing_hint}\" >&2"
                    io.puts "    exit 127"
                    io.puts "fi"
                end
                io.puts "exec #{([python_executable] + args).join(' ')} \"$@\""
            end
            FileUtils.chmod 0o755, path
            path
        end

        def self.rewrite_python_shims(python_executable, prefix_dir)
            write_shim("python", python_executable, prefix_dir)
        end

        def self.rewrite_pip_shims(python_executable, prefix_dir)
            write_shim("pip", python_executable, prefix_dir, args: %w[-m pip])
        end

        # Point the python and pip shims to the workspace's venv
        #
        # The shims are written even if the venv does not exist (yet), so that
        # the system python is never used by accident
        def self.rewrite_venv_shims(ws: Autoproj.workspace)
            python = venv_python(ws: ws)
            hint = "autoproj: #{python} does not exist, " \
                   "running 'autoproj osdeps' will likely fix this"
            write_shim("python", python, ws.dot_autoproj_dir, missing_hint: hint)
            write_shim("pip", python, ws.dot_autoproj_dir,
                       args: %w[-m pip], missing_hint: hint)
        end

        # The value stored for a configuration option, without asking the user
        # and without requiring the option to be declared
        def self.stored_config_value(ws, name)
            return ws.config.overrides[name] if ws.config.overrides.key?(name)

            ws.config.config.dig(name, 0)
        end

        # Path to the workspace's python venv
        #
        # It only contains packages installed by the pip package manager and can
        # be deleted at any time; 'autoproj osdeps' recreates it
        def self.venv_path(ws: Autoproj.workspace)
            File.join(ws.prefix_dir, "venv")
        end

        def self.venv_python(ws: Autoproj.workspace)
            File.join(venv_path(ws: ws), "bin", "python")
        end

        def self.venv_uv(ws: Autoproj.workspace)
            File.join(venv_path(ws: ws), "bin", "uv")
        end

        # Whether python packages are installed into the workspace's venv
        #
        # Only looks at the stored configuration, i.e. never asks the user. Also
        # serves package sets as the test whether autoproj supports venvs.
        def self.venv_enabled?(ws: Autoproj.workspace)
            stored_config_value(ws, "USE_PYTHON") == true &&
                stored_config_value(ws, "USE_PYTHON_VENV") == true
        end

        # Whether pip packages are installed with uv (only used with a venv)
        def self.uv_enabled?(ws: Autoproj.workspace)
            venv_enabled?(ws: ws) && stored_config_value(ws, "USE_PYTHON_UV") == true
        end

        # Directory used as PYTHONUSERBASE if the venv is disabled
        def self.pip_home(ws: Autoproj.workspace)
            ws.env["AUTOPROJ_PYTHONUSERBASE"] || File.join(ws.prefix_dir, "pip")
        end

        # Whether the given python is marked as externally managed (PEP 668),
        # i.e. refuses to install packages with pip outside of a venv
        def self.externally_managed?(python_bin)
            @externally_managed ||= {}
            return @externally_managed[python_bin] if @externally_managed.key?(python_bin)

            script = "import os, sysconfig; print(os.path.isfile(os.path.join(" \
                     "sysconfig.get_path('stdlib'), 'EXTERNALLY-MANAGED')))"
            msg, status = Open3.capture2e(python_bin, "-c", script)
            @externally_managed[python_bin] = status.success? && msg.strip == "True"
        rescue SystemCallError
            @externally_managed[python_bin] = false
        end

        # Version of the python a venv has been created with, read from its
        # pyvenv.cfg
        #
        # @return [String,nil]
        def self.venv_python_version(path)
            cfg = File.join(path, "pyvenv.cfg")
            return unless File.file?(cfg)

            File.readlines(cfg).each do |line|
                key, value = line.split("=", 2).map(&:strip)
                return value if %w[version version_info].include?(key)
            end
            nil
        end

        # Whether the venv exists and matches the configured python version
        def self.venv_valid?(ws: Autoproj.workspace)
            path = venv_path(ws: ws)
            return false unless File.executable?(venv_python(ws: ws))

            venv_version = venv_python_version(path)
            version = ws.config.get("python_version", nil)
            return false unless venv_version && version

            venv_version == version || venv_version.start_with?("#{version}.")
        end

        # Commands needed to create or complete the venv, empty if it is
        # complete
        #
        # Running them requires deleting an invalid venv first, see
        # {prepare_venv}
        #
        # @return [Array<Array<String>>]
        def self.venv_setup_cmdlines(ws: Autoproj.workspace)
            python = venv_python(ws: ws)
            cmdlines = []
            unless venv_valid?(ws: ws)
                cmdlines << [ws.config.get("python_executable"), "-m", "venv",
                             "--system-site-packages", venv_path(ws: ws)]
                cmdlines << [python, "-m", "pip", "install", "--upgrade", "pip"]
            end
            needs_uv = !cmdlines.empty? || !File.executable?(venv_uv(ws: ws))
            if uv_enabled?(ws: ws) && needs_uv
                cmdlines << [python, "-m", "pip", "install", "uv"]
            end
            cmdlines
        end

        # Delete the venv if it is invalid, so that it can be recreated
        #
        # @return [Boolean] true if the venv needs to be created
        def self.prepare_venv(ws: Autoproj.workspace)
            return false if venv_valid?(ws: ws)

            path = venv_path(ws: ws)
            if File.exist?(path)
                Autoproj.message "  recreating the python venv in #{path}"
                FileUtils.rm_rf path
            else
                Autoproj.message "  creating a python venv in #{path}"
            end
            true
        end

        # Set up the environment for the python installation
        #
        # @param [Boolean] venv whether the venv is enabled
        def self.setup_environment(ws: Autoproj.workspace, venv: venv_enabled?(ws: ws))
            venv_bin = File.join(venv_path(ws: ws), "bin")
            pip_bin = File.join(pip_home(ws: ws), "bin")
            if venv
                remove_from_path(ws.env, pip_bin)
                setup_venv_environment(ws)
            else
                remove_from_path(ws.env, venv_bin)
                setup_user_site_environment(ws)
            end
        end

        def self.remove_from_path(env, dir)
            env.remove_path "PATH", dir if env.environment["PATH"]
        end

        def self.setup_venv_environment(ws)
            env = ws.env
            env.unset "PYTHONUSERBASE"
            # With --system-site-packages, the user site would be visible too
            env.set "PYTHONNOUSERSITE", "1"
            env.set "VIRTUAL_ENV", venv_path(ws: ws)
            env.add_path "PATH", File.join(venv_path(ws: ws), "bin")
        end

        def self.setup_user_site_environment(ws)
            env = ws.env
            env.reset "PYTHONNOUSERSITE"
            env.reset "VIRTUAL_ENV"
            env.set "PYTHONUSERBASE", pip_home(ws: ws)
            env.add_path "PATH", File.join(pip_home(ws: ws), "bin")
        end

        # Activate configuration for python in the autoproj configuration
        # @return [String,String] python path and python version
        def self.activate_python(ws: Autoproj.workspace,
            bin: nil,
            version: nil)
            bin, version = resolve_python(ws: ws, bin: bin, version: version)
            ws.config.set("python_executable", bin, true)
            ws.config.set("python_version", version, true)

            ws.osdep_suffixes << "python#{$1}" if version =~ /^([0-9]+)\./

            venv = venv_enabled?(ws: ws)
            if venv
                rewrite_venv_shims(ws: ws)
            else
                rewrite_python_shims(bin, ws.dot_autoproj_dir)
                rewrite_pip_shims(bin, ws.dot_autoproj_dir)
            end
            setup_environment(ws: ws, venv: venv)
            [bin, version]
        end

        def self.deactivate_python(ws: Autoproj.workspace)
            remove_python_shims(ws.dot_autoproj_dir)
            remove_pip_shims(ws.dot_autoproj_dir)
            ws.config.reset("python_executable")
            ws.config.reset("python_version")
        end

        # Allow to update the PYTHONPATH for package if autoproj configuration
        # USE_PYTHON is set to true.
        # Then tries to guess the python binary from Autobuild.programs['python']
        # and system's default setting
        # @param [Autobuild::Package] pkg
        # @param [Autoproj.workspace] ws Autoproj workspace
        # @param [String] bin Path to a custom python version
        # @param [String] version version constraint for python executable
        # @return tuple of [executable, version, site-packages path] if set,
        #    otherwise nil
        def self.activate_python_path(pkg,
            ws: Autoproj.workspace,
            bin: nil,
            version: nil)
            return unless ws.config.get("USE_PYTHON", nil)

            bin, version = resolve_python(ws: ws, bin: bin, version: version)
            path = File.join(pkg.prefix, "lib",
                             "python#{version}", "site-packages")
            pkg.env_add_path "PYTHONPATH", path

            [bin, version, path]
        end

        def self.assert_python_activated(ws: Autoproj.workspace)
            return true if ws.config.get("USE_PYTHON")

            raise ConfigError,
                  "Your current package selection requires the use of python," \
                  " but this is either unspecified or has been denied,"\
                  " see setting of USE_PYTHON in your workspace configuration." \
                  " Either remove all packages depending on pip packages " \
                  " from the workspace layout (manifest) or " \
                  " call 'autoproj reconfigure' to change the setting."
        end

        def self.setup_python_configuration_options(ws: Autoproj.workspace)
            ws.config.declare "USE_PYTHON", "boolean",
                              default: "no",
                              doc: ["Do you want to activate python?"]

            if ws.config.get("USE_PYTHON")
                migrate_package_set_venv_configuration(ws)
                declare_python_executable(ws)
                setup_venv_configuration_options(ws)
                activate_python(ws: ws)
            else
                deactivate_python(ws: ws)
            end
        end

        def self.declare_python_executable(ws)
            unless ws.config.has_value_for?("python_executable")
                remove_python_shims(ws.dot_autoproj_dir)
                remove_pip_shims(ws.dot_autoproj_dir)
                python_bin, = auto_resolve_python(ws: ws)
            end

            ws.config.declare "python_executable", "string",
                              default: python_bin.to_s,
                              doc: ["Select the path to the python executable"]
        end

        # Get a boolean option, storing it even if it is the default (non-interactive
        # mode), as venv_enabled? and uv_enabled? only read stored values
        def self.get_and_store(ws, name)
            value = ws.config.get(name)
            ws.config.set(name, value, true)
            value
        end

        def self.setup_venv_configuration_options(ws)
            was_enabled = stored_config_value(ws, "USE_PYTHON_VENV")
            declare_venv_option(ws) unless ws.config.declared?("USE_PYTHON_VENV")
            enabled = get_and_store(ws, "USE_PYTHON_VENV")
            if was_enabled != enabled && !was_enabled.nil?
                venv_toggled_message(ws, enabled)
            end
            return unless enabled

            ws.config.declare "USE_PYTHON_UV", "boolean",
                              default: "yes",
                              doc: ["Install python packages into the venv using uv?",
                                    "uv hardlinks packages from a cache shared between "\
                                    "workspaces, which saves space and time"]
            get_and_store(ws, "USE_PYTHON_UV")
        end

        def self.declare_venv_option(ws)
            python_bin = ws.config.get("python_executable")
            default = externally_managed?(python_bin) ? "yes" : "no"
            ws.config.declare "USE_PYTHON_VENV", "boolean",
                              default: default,
                              doc: ["Install python packages into a venv in the "\
                                    "install folder?",
                                    "This is required if the python interpreter is "\
                                    "externally managed (PEP 668),",
                                    "e.g. on Ubuntu 24.04"]
        end

        def self.venv_toggled_message(ws, enabled)
            state = enabled ? "enabled" : "disabled"
            Autoproj.message "  the python venv has been #{state}"
            Autoproj.message "  packages built before may still refer to the previous " \
                             "python installation and need to be rebuilt"
            if enabled
                Autoproj.message "  run 'autoproj osdeps' to create the venv"
            elsif File.directory?(path = venv_path(ws: ws))
                Autoproj.message "  #{path} is not used anymore and can be deleted"
            end
        end

        # Convert the configuration of the venv implementation in Rock's package set
        #
        # It stored the venv's python as python_executable, which breaks once the
        # venv gets deleted
        def self.migrate_package_set_venv_configuration(ws)
            if (venv = stored_config_value(ws, "PYTHON_VENV_FOLDER"))
                current = stored_config_value(ws, "python_executable")
                if current&.start_with?(File.join(venv, ""))
                    if (bin = stored_config_value(ws, "PYTHON_VENV_INIT_EXECUTABLE"))
                        ws.config.set("python_executable", bin, true)
                    else
                        ws.config.reset("python_executable")
                    end
                end
            end
            %w[PYTHON_VENV_FOLDER PYTHON_VENV_INIT_EXECUTABLE].each do |name|
                ws.config.reset(name) if ws.config.has_value_for?(name)
            end
        end
    end
end
