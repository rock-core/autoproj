require "autoproj/python"

module Autoproj
    module PackageManagers
        # Using pip to install python packages
        class PipManager < Manager
            attr_reader :installed_pips

            def initialize_environment
                Autoproj::Python.setup_environment(ws: ws)
            end

            # Return the directory where python packages are installed to if
            # the venv is disabled.
            # The actual path is pip_home/lib/pythonx.y/site-packages.
            def pip_home
                Autoproj::Python.pip_home(ws: ws)
            end

            def initialize(ws)
                super(ws)
                @installed_pips = Set.new
            end

            # Called even without pip packages to create a missing venv, which
            # python source packages need as well
            def call_while_empty?
                Autoproj::Python.venv_enabled?(ws: ws)
            end

            def os_dependencies
                deps = super + ["pip"]
                deps << "python-venv" if Autoproj::Python.venv_enabled?(ws: ws)
                deps
            end

            def guess_pip_program
                activate_python
                Autobuild.programs["pip"] = "pip" unless Autobuild.programs["pip"]
                Autobuild.programs["pip"]
            end

            def activate_python
                Autoproj::Python.setup_python_configuration_options(ws: ws)
                Autoproj::Python.assert_python_activated(ws: ws)
            end

            # The command line that installs the given packages
            def install_cmdline(pips)
                if Autoproj::Python.uv_enabled?(ws: ws)
                    python = Autoproj::Python.venv_python(ws: ws)
                    [Autoproj::Python.venv_uv(ws: ws), "pip", "install",
                     "--python", python] + pips
                elsif Autoproj::Python.venv_enabled?(ws: ws)
                    [Autoproj::Python.venv_python(ws: ws), "-m", "pip", "install"] + pips
                else
                    [Autobuild.tool("pip"), "install", "--user"] + pips
                end
            end

            def install(pips, filter_uptodate_packages: false, install_only: false)
                pips = [pips] if pips.is_a?(String)
                return if pips.empty? && !Autoproj::Python.venv_enabled?(ws: ws)

                guess_pip_program
                cmdlines = install_cmdlines(pips)
                return if cmdlines.empty? || !pips_interaction(cmdlines)

                run_install(cmdlines, pips)
            end

            # All commands needed to install the given packages, including the
            # creation of the venv if needed
            def install_cmdlines(pips)
                cmdlines = []
                if Autoproj::Python.venv_enabled?(ws: ws)
                    cmdlines.concat(Autoproj::Python.venv_setup_cmdlines(ws: ws))
                end
                cmdlines << install_cmdline(pips) unless pips.empty?
                cmdlines
            end

            def run_install(cmdlines, pips)
                venv = Autoproj::Python.venv_enabled?(ws: ws)
                Autoproj::Python.prepare_venv(ws: ws) if venv
                unless pips.empty?
                    Autoproj.message "  installing/updating Python dependencies:" \
                                     " #{pips.sort.join(', ')}"
                end

                cmdlines.each { |c| run_cmdline(c) }
                @installed_pips.merge(pips)
            end

            def run_cmdline(cmdline)
                Autobuild::Subprocess.run "autoproj", "osdeps", *cmdline,
                                          env: ws.env.resolved_env
            rescue Autobuild::SubcommandFailed => e
                raise unless cmdline[1..2] == %w[-m venv]

                FileUtils.rm_rf Autoproj::Python.venv_path(ws: ws)
                raise ConfigError, "failed to create the python venv " \
                                   "(on Debian/Ubuntu, this requires the python3-venv " \
                                   "package): #{e.message}"
            end

            def pips_interaction(cmdlines)
                if OSPackageInstaller.force_osdeps
                    return true
                elsif enabled?
                    return true
                elsif silent?
                    return false
                end

                # We're not supposed to install rubygem packages but silent is not
                # set, so display information about them anyway
                puts <<-EOMSG
      #{Autoproj.color('The build process and/or the packages require some Python packages to be installed', :bold)}
      #{Autoproj.color('and you required autoproj to not do it itself', :bold)}
        The following command line can be used to install them manually
#{'        '}
          #{cmdlines.map { |c| c.join(' ') }.join("\n      ")}
#{'        '}
        #{install_location_message}

                EOMSG
                print "    #{Autoproj.color('Press ENTER to continue ', :bold)}"

                $stdout.flush
                $stdin.readline
                puts
                false
            end

            def install_location_message
                if Autoproj::Python.venv_enabled?(ws: ws)
                    "Autoproj expects these Python packages to be installed in the " \
                        "venv #{Autoproj::Python.venv_path(ws: ws)}"
                else
                    "Autoproj expects these Python packages to be installed in " \
                        "#{pip_home} This can\n        be overridden by setting the " \
                        "AUTOPROJ_PYTHONUSERBASE environment variable manually"
                end
            end
        end
    end
end
